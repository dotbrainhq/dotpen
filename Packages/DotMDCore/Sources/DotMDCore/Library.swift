import Foundation
import Observation

/// Whether DotMD can reach a watched folder.
public enum FolderStatus: Sendable, Equatable {
    /// Listed, with its bookmark not resolved yet.
    case connecting
    /// Resolved and watched. Its scan may still be queued or running.
    case ready
    /// The bookmark didn't resolve or the folder went away. Its rows and read state are kept until it reconnects.
    case accessLost
}

/// One watched folder as the file list shows it.
public struct FolderState: Identifiable, Equatable, Sendable {
    public var folder: WatchedFolder
    public var status: FolderStatus
    /// The folder's real location while it is ready. Nil while connecting and when access was lost.
    public var url: URL?
    public var branch: String?
    public var documents: [Document]
    /// Paths hidden by ignore rules, relative to the folder.
    public var ignored: [String]

    public init(folder: WatchedFolder, status: FolderStatus, url: URL? = nil, branch: String? = nil,
                documents: [Document] = [], ignored: [String] = []) {
        self.folder = folder
        self.status = status
        self.url = url
        self.branch = branch
        self.documents = documents
        self.ignored = ignored
    }

    public var id: Int64 { folder.id ?? 0 }
    public var accessLost: Bool { status == .accessLost }
    public var isConnecting: Bool { status == .connecting }
    public var unreadCount: Int { documents.filter { $0.readState != .read }.count }
}

/// Watched folders and their Markdown, kept current as files change. Lives on the main actor for SwiftUI;
/// scanning and hashing run on background tasks.
@MainActor
@Observable
public final class Library {
    public private(set) var folders: [FolderState] = []
    /// Whether start() has read the stored folders, so an empty list means no folders rather than not loaded yet.
    public private(set) var hasLoaded = false
    /// Goes up whenever a comment is added, edited, resolved, sent or deleted, so views showing comments reload.
    public private(set) var commentsVersion = 0
    /// Documents being written right now: changed within the last few seconds.
    public private(set) var writing: Set<Int64> = []
    /// Shows paths the ignore rules would hide. Changing it rescans every folder; the newest setting wins.
    public var showIgnored = false {
        didSet {
            guard showIgnored != oldValue else { return }
            rescanAllTask?.cancel()
            rescanAllTask = Task { await rescanAll() }
        }
    }
    /// While set, file events wait: the list stops moving until this time, then a rescan catches up.
    public private(set) var pausedUntil: Date?
    /// How long a file counts as being written after its last change.
    @ObservationIgnored public var writingQuietPeriod: Duration = .seconds(3)

    @ObservationIgnored private let database: LibraryDatabase
    @ObservationIgnored private var watchers: [Int64: FolderWatcher] = [:]
    @ObservationIgnored private var writingTimers: [Int64: Task<(), Never>] = [:]
    /// Content hashes of writes DotMD made itself, a ticked task: the change they bring isn't an agent writing.
    @ObservationIgnored private var ownWrites: Set<String> = []
    @ObservationIgnored private var started = false
    /// The URL each folder's security-scoped access was started on. Paths use the canonical root instead.
    @ObservationIgnored private var accessURLs: [Int64: URL] = [:]
    /// The newest job per folder. Scans and event batches for one folder run one after another.
    @ObservationIgnored private var folderWork: [Int64: Task<(), Never>] = [:]
    @ObservationIgnored private var rescanAllTask: Task<(), Never>?
    /// A queued rescan per folder that hasn't started yet. Later requests wait on it instead of queuing another.
    @ObservationIgnored private var pendingRescans: [Int64: Task<(), Never>] = [:]
    /// Folders that had events while watching was paused.
    @ObservationIgnored private var missedWhilePaused: Set<Int64> = []
    @ObservationIgnored private var resumeTask: Task<(), Never>?

    public init(database: LibraryDatabase) {
        self.database = database
    }

    // MARK: Folders

    /// Opens every stored folder and starts watching it, then indexes them and returns when every scan has run.
    /// Every folder is resolved before any scan starts, so one waiting its turn never reads as access lost.
    /// Calling it again does nothing.
    public func start() async {
        guard !started else { return }
        started = true
        let stored = (try? database.folders()) ?? []
        folders = stored.map { folder in
            FolderState(folder: folder, status: .connecting, documents: (try? database.documents(folderID: folder.id ?? 0)) ?? [])
        }
        hasLoaded = true
        var ready: [Int64] = []
        for folder in stored where connect(folder) {
            if let id = folder.id { ready.append(id) }
        }
        let scans = ready.map { ($0, queueRescan($0)) }
        for (id, scan) in scans {
            await scan.value
            if folderWork[id] == scan { folderWork[id] = nil }
        }
    }

    /// Watches a folder the person chose. Adding a folder that is already watched does nothing, unless its access
    /// was lost: then it reconnects to the new URL.
    public func addFolder(_ url: URL) async throws {
        let root = FolderAccess.canonical(url)
        if let existing = folders.first(where: { $0.folder.path == root.path }) {
            if existing.accessLost { try await reconnect(existing.id, to: url) }
            return
        }
        let bookmark = try FolderAccess.bookmark(for: url)
        let folder = try database.insert(WatchedFolder(
            bookmark: bookmark,
            path: root.path,
            name: root.lastPathComponent,
            color: .next(after: folders.map(\.folder.color))
        ))
        folders.append(FolderState(folder: folder, status: .connecting))
        await open(folder)
    }

    /// Points a folder whose access was lost at the location the person chose again. Read state is kept.
    public func reconnect(_ id: Int64, to url: URL) async throws {
        guard var folder = state(id)?.folder else { return }
        folder.bookmark = try FolderAccess.bookmark(for: url)
        folder.path = FolderAccess.canonical(url).path
        try database.update(folder)
        await open(folder)
    }

    public func removeFolder(_ id: Int64) {
        watchers.removeValue(forKey: id)?.cancel()
        releaseAccess(id)
        try? database.deleteFolder(id: id)
        folders.removeAll { $0.id == id }
    }

    public func setColor(_ color: FolderColor, for id: Int64) {
        guard var folder = state(id)?.folder else { return }
        folder.color = color
        try? database.update(folder)
        update(id) { $0.folder = folder }
    }

    // MARK: Documents

    public func url(for document: Document) -> URL? {
        state(document.folderID)?.url?.appending(path: document.relativePath)
    }

    /// The watched folder a file sits in, if any.
    public func folder(containing fileURL: URL) -> FolderState? {
        let path = FolderAccess.canonical(fileURL).path
        return folders.first { folder in
            guard let root = folder.url?.path else { return false }
            return path.hasPrefix(root + "/")
        }
    }

    public func document(at fileURL: URL) -> Document? {
        guard let folder = folder(containing: fileURL), let root = folder.url else { return nil }
        let relativePath = String(FolderAccess.canonical(fileURL).path.dropFirst(root.path.count + 1))
        return folder.documents.first { $0.relativePath == relativePath }
    }

    /// A document by its key, searched across the watched folders.
    public func document(key: Int64) -> Document? {
        for folder in folders {
            if let match = folder.documents.first(where: { $0.key == key }) { return match }
        }
        return nil
    }

    /// Marks a document read at its text on disk now, and keeps that text for the next diff.
    public func markRead(_ document: Document) async {
        guard let url = url(for: document) else { return }
        let data = await Task.detached { try? Data(contentsOf: url) }.value
        let updated = if let data {
            try? database.markRead(documentID: document.key, content: data)
        } else {
            try? database.markRead(documentID: document.key)
        }
        if let updated { put(updated) }
    }

    /// Marks a document read at the text the reader showed, so the snapshot is exactly what the person saw.
    public func markRead(_ document: Document, text: String) {
        if let updated = try? database.markRead(documentID: document.key, content: Data(text.utf8)) { put(updated) }
    }

    /// Swaps the text kept as last read, keeping when it was read: a task ticked in DotMD isn't a change to review.
    public func replaceReadText(_ document: Document, with text: String) {
        let readAt = lastReadDate(for: document) ?? .now
        if let updated = try? database.markRead(documentID: document.key, content: Data(text.utf8), at: readAt) { put(updated) }
    }

    /// DotMD is about to write this content to a watched file itself.
    public func expectOwnWrite(_ content: Data) {
        ownWrites.insert(Snapshots.hash(content))
    }

    /// The text the person last read, when DotMD kept it.
    public func lastReadText(for document: Document) -> String? {
        guard let hash = document.readHash else { return nil }
        return try? database.snapshotText(hash: hash)
    }

    /// When the person last read the file. Files read by a folder's first scan, or before read times were kept,
    /// date from when DotMD kept their text.
    public func lastReadDate(for document: Document) -> Date? {
        if let date = document.lastReadAt { return date }
        guard let hash = document.readHash else { return nil }
        return try? database.snapshotTakenAt(hash: hash)
    }

    // MARK: Comments

    /// A document's comments, each with where its passage is in the text now (nil when no block shows it).
    /// Comments whose passage moved are saved at their new lines.
    public func comments(for document: Document, text: String) -> [PlacedComment] {
        let stored = (try? database.comments(documentID: document.key)) ?? []
        return stored.map { comment in
            let range = CommentAnchor.locate(quote: comment.quote, near: comment.lineStart, in: text)
            if let range, range.start != comment.lineStart || range.end != comment.lineEnd {
                var moved = comment
                moved.lineStart = range.start
                moved.lineEnd = range.end
                try? database.update(moved)
                return PlacedComment(comment: moved, range: range)
            }
            return PlacedComment(comment: comment, range: range)
        }
    }

    /// Saves a new comment on a passage of the text the reader shows.
    @discardableResult
    public func addComment(to document: Document, quote: String, line: Int, body: String, text: String) -> Comment? {
        let block = CommentAnchor.block(containing: line, in: text)
        let comment = Comment(
            documentID: document.key,
            quote: quote,
            lineStart: block?.startLine ?? line,
            lineEnd: block?.endLine ?? line,
            contextHash: CommentAnchor.contextHash(of: block?.source ?? quote),
            body: body
        )
        guard let saved = try? database.insert(comment) else { return nil }
        commentsVersion += 1
        return saved
    }

    public func editComment(_ comment: Comment, body: String) {
        var edited = comment
        edited.body = body
        // An edited comment goes out again with the next Send.
        edited.sentAt = nil
        save(edited)
    }

    public func setResolved(_ comment: Comment, _ resolved: Bool) {
        var changed = comment
        changed.status = resolved ? .resolved : .open
        save(changed)
    }

    public func markSent(_ comments: [Comment], at date: Date = .now, resolve: Bool) {
        for comment in comments {
            var sent = comment
            sent.sentAt = date
            if resolve { sent.status = .resolved }
            try? database.update(sent)
        }
        commentsVersion += 1
    }

    public func deleteComment(_ comment: Comment) {
        try? database.deleteComment(id: comment.key)
        commentsVersion += 1
    }

    /// Every open comment in the library with its document.
    public func openComments() -> [(Comment, Document)] {
        (try? database.openComments()) ?? []
    }

    private func save(_ comment: Comment) {
        try? database.update(comment)
        commentsVersion += 1
    }

    public func setReadLine(_ document: Document, line: Int) {
        if let updated = try? database.setReadLine(documentID: document.key, line: line) { put(updated) }
    }

    public func markUnread(_ document: Document) {
        if let updated = try? database.markUnread(documentID: document.key) { put(updated) }
    }

    public func setPinned(_ document: Document, _ pinned: Bool) {
        if let updated = try? database.setPinned(documentID: document.key, pinned) { put(updated) }
    }

    // MARK: Indexing

    /// Connects, then scans. The watcher starts first so changes made during the scan aren't lost: their batches
    /// queue behind the scan and apply after it.
    private func open(_ folder: WatchedFolder) async {
        guard let id = folder.id, connect(folder) else { return }
        await rescan(id)
        if state(id) == nil {
            // Removed while the scan ran. removeFolder already let go of both; this keeps a late open from holding them.
            watchers.removeValue(forKey: id)?.cancel()
            releaseAccess(id)
        }
    }

    /// Resolves the folder's bookmark and starts watching it. Returns false, with the folder marked access lost,
    /// when the bookmark doesn't resolve, or finds the folder gone or in the Trash.
    private func connect(_ folder: WatchedFolder) -> Bool {
        guard let id = folder.id else { return false }
        watchers.removeValue(forKey: id)?.cancel()
        // The new access starts before the old one stops, so the folder is never left without a grant in between.
        var resolved = try? FolderAccess.resolve(folder.bookmark)
        releaseAccess(id)
        if let found = resolved, FolderAccess.isInTrash(found.url) || !Self.isDirectory(found.url) {
            FolderAccess.stop(found.url)
            resolved = nil
        }
        guard let resolved else {
            update(id) { state in
                state.url = nil
                state.status = .accessLost
            }
            return false
        }
        accessURLs[id] = resolved.url
        var folder = folder
        let root = FolderAccess.canonical(resolved.url)
        if let fresh = resolved.refreshedBookmark { folder.bookmark = fresh }
        folder.path = root.path
        try? database.update(folder)
        update(id) { state in
            state.folder = folder
            state.url = root
            state.status = .ready
        }
        watchers[id] = FolderWatcher(url: root) { [weak self] events in
            Task { @MainActor [weak self] in await self?.handle(events, in: id) }
        }
        return true
    }

    private func releaseAccess(_ id: Int64) {
        if let url = accessURLs.removeValue(forKey: id) { FolderAccess.stop(url) }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// The folder's root went away. A moved folder's bookmark still finds it, so DotMD watches it there, as a relaunch
    /// would, and scans it behind the current job. A deleted folder keeps its rows and read state and shows as
    /// needing reconnection.
    private func loseAccess(_ id: Int64) {
        if let folder = state(id)?.folder, connect(folder) {
            _ = queueRescan(id)
            return
        }
        watchers.removeValue(forKey: id)?.cancel()
        releaseAccess(id)
        update(id) { state in
            state.url = nil
            state.status = .accessLost
        }
    }

    /// Runs work after every earlier job for the same folder has finished, and returns when it has run.
    /// Work must not call serialized for the same folder, or it waits on itself.
    private func serialized(_ id: Int64, _ work: @escaping @MainActor () async -> ()) async {
        let task = enqueue(id, work)
        await task.value
        if folderWork[id] == task { folderWork[id] = nil }
    }

    private func enqueue(_ id: Int64, _ work: @escaping @MainActor () async -> ()) -> Task<(), Never> {
        let previous = folderWork[id]
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        folderWork[id] = task
        return task
    }

    private func rescanAll() async {
        for id in folders.map(\.id) {
            guard !Task.isCancelled else { return }
            await rescan(id)
        }
    }

    /// Queues a rescan and returns once it has run.
    private func rescan(_ id: Int64) async {
        let task = queueRescan(id)
        await task.value
        if folderWork[id] == task { folderWork[id] = nil }
    }

    /// Queues a rescan behind the folder's earlier work. A rescan that is queued and not started yet already covers
    /// this request, so that one is returned instead. Merging is safe for a first scan too: the database decides
    /// which scan is first when it writes.
    private func queueRescan(_ id: Int64) -> Task<(), Never> {
        if let pending = pendingRescans[id] { return pending }
        let task = enqueue(id) { [weak self] in
            self?.pendingRescans[id] = nil
            await self?.performRescan(id)
        }
        pendingRescans[id] = task
        return task
    }

    private func performRescan(_ id: Int64) async {
        guard let root = state(id)?.url else { return }
        let showIgnored = showIgnored
        let rules = showIgnored ? IgnoreRules.none : IgnoreRules.load(root: root)
        let usualRules = showIgnored ? IgnoreRules.load(root: root) : nil
        let scan = await Task.detached(priority: .utility) { () -> (ScanResult, Set<String>)? in
            guard let result = FolderScanner.scan(root: root, rules: rules) else { return nil }
            // Files that only show because ignored paths are shown arrive as read, so toggling doesn't add unread files.
            let shownByToggle = usualRules.map { usual in
                Set(result.files.map(\.relativePath).filter { usual.containsIgnoredPath($0) })
            } ?? []
            return (result, shownByToggle)
        }.value
        // Removed or reconnected elsewhere while scanning: these results belong to nothing now.
        guard state(id)?.url == root else { return }
        // A vanished root can't be scanned. Writing nothing keeps every row and its read state.
        guard FileManager.default.fileExists(atPath: root.path) else {
            loseAccess(id)
            return
        }
        // The root is there but couldn't be read: an empty result would read as every file deleted.
        guard let (result, shownByToggle) = scan else { return }
        let database = database
        await Task.detached(priority: .utility) {
            try? database.replaceDocuments(folderID: id, with: result.files, unreadable: Set(result.unreadable),
                                           readPaths: shownByToggle)
        }.value
        guard state(id) != nil else { return }
        let indexedAt = (try? database.folder(id: id))?.indexedAt
        let branch = GitBranch.current(in: root)
        update(id) { state in
            state.folder.indexedAt = indexedAt
            state.ignored = result.ignored
            state.branch = branch
        }
        reloadDocuments(id)
    }

    // MARK: Pausing

    /// Stops reacting to file changes for a while, as the menu bar item's "Pause watching for 1 hour" does.
    public func pauseWatching(for duration: Duration) {
        pausedUntil = Date.now.addingTimeInterval(TimeInterval(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await self?.resumeWatching()
        }
    }

    /// Watches again, and rescans the folders that changed meanwhile.
    public func resumeWatching() async {
        resumeTask?.cancel()
        resumeTask = nil
        pausedUntil = nil
        let missed = missedWhilePaused
        missedWhilePaused = []
        for id in missed { await rescan(id) }
    }

    /// Test hook: builds events from the disk as it is now, since plain paths carry no flags. A path that exists is a
    /// folder when the disk says so. A missing path is removed, and counts as a folder when stored documents sit under it.
    func handle(_ paths: [String], in id: Int64) async {
        let root = state(id)?.url?.path
        let stored = state(id)?.documents.map(\.relativePath) ?? []
        let events = paths.map { path in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            var wasFolder = false
            if !exists, let root, path.hasPrefix(root + "/") {
                let prefix = String(path.dropFirst(root.count + 1)) + "/"
                wasFolder = stored.contains { $0.hasPrefix(prefix) }
            }
            return FolderEvent(path: path, isDirectory: isDirectory.boolValue || wasFolder, isRemoved: !exists, isRenamed: false)
        }
        await handle(events, in: id)
    }

    /// Applies one batch of file events for a folder, after any earlier work for it. A batch that needs a full
    /// rescan queues one afterwards, merged with any rescan already waiting.
    func handle(_ events: [FolderEvent], in id: Int64) async {
        if pausedUntil != nil {
            missedWhilePaused.insert(id)
            return
        }
        var needsRescan = false
        await serialized(id) { [weak self] in needsRescan = await self?.apply(events, in: id) ?? false }
        if needsRescan { await rescan(id) }
    }

    /// Returns true when the folder needs a full rescan: a folder event outside the ignore rules, the root .gitignore,
    /// a batch where FSEvents dropped or merged events, or more than maxFilesPerBatch Markdown files. Otherwise a
    /// Markdown file updates its own row and other files are skipped, except .git/HEAD (branch). The root going away
    /// loses access.
    private func apply(_ events: [FolderEvent], in id: Int64) async -> Bool {
        guard let root = state(id)?.url else { return false }
        let rootPath = root.path
        // Checked for every batch, not only one naming the root: removals under a moved root can arrive before the
        // root's own event, and would delete rows (or a rescan would find nothing) for a folder that only moved.
        if !FileManager.default.fileExists(atPath: rootPath) {
            loseAccess(id)
            return false
        }
        // Dropped or merged events name a folder, often the root, and may not carry ItemIsDir.
        if events.contains(where: \.mustScanSubDirs) { return true }
        let rules = showIgnored ? IgnoreRules.none : IgnoreRules.load(root: root)
        let usualRules = showIgnored ? IgnoreRules.load(root: root) : nil
        var files: Set<String> = []
        var needsRescan = false
        var branchChanged = false
        for event in events {
            let path = trimmed(event.path)
            guard path.hasPrefix(rootPath + "/") else { continue }
            let relativePath = String(path.dropFirst(rootPath.count + 1))
            if relativePath == ".git/HEAD" {
                branchChanged = true
                continue
            }
            // Before the ignore rules, so a rule like ".*" can't hide the file the rules come from.
            if relativePath == ".gitignore" {
                needsRescan = true
                continue
            }
            // .git folders are skipped at any depth, as the scanner does, even with ignored paths shown.
            if relativePath.split(separator: "/").contains(".git") || rules.containsIgnoredPath(relativePath) { continue }
            if event.isDirectory {
                needsRescan = true
            } else if FolderScanner.isMarkdown(URL(fileURLWithPath: path)) {
                files.insert(relativePath)
            }
        }
        // One rescan transaction is cheaper than a transaction per file once a batch gets big (a checkout, a pull).
        if needsRescan || files.count > Self.maxFilesPerBatch { return true }
        if branchChanged {
            let branch = GitBranch.current(in: root)
            update(id) { $0.branch = branch }
        }
        guard !files.isEmpty else { return false }
        for relativePath in files.sorted() {
            let url = root.appending(path: relativePath)
            let file = await Task.detached(priority: .utility) { FolderScanner.summarize(fileURL: url, relativePath: relativePath) }.value
            guard state(id)?.url == root else { return false }
            guard let file else {
                // A file that vanished with its root isn't deleted: the folder only lost access.
                guard FileManager.default.fileExists(atPath: rootPath) else {
                    loseAccess(id)
                    return false
                }
                // A file that is there but couldn't be read keeps its row. Only a file that is gone loses it.
                guard FolderScanner.isGone(url.path) else { continue }
                try? database.deleteDocument(folderID: id, relativePath: relativePath)
                update(id) { $0.documents.removeAll { $0.relativePath == relativePath } }
                continue
            }
            let before = try? database.document(folderID: id, relativePath: relativePath)
            // As in a rescan, a file that only shows because ignored paths are shown arrives as read.
            let shownByToggle = usualRules?.containsIgnoredPath(relativePath) ?? false
            if let stored = try? database.upsert(file, folderID: id, readIfNew: shownByToggle) {
                put(stored)
                if before?.contentHash != stored.contentHash, ownWrites.remove(stored.contentHash) == nil {
                    markWriting(stored.key)
                }
            }
        }
        return false
    }

    /// Above this many Markdown files in one batch, a full rescan replaces the per-file updates.
    static let maxFilesPerBatch = 50

    private func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func markWriting(_ documentID: Int64) {
        writing.insert(documentID)
        writingTimers[documentID]?.cancel()
        let quiet = writingQuietPeriod
        writingTimers[documentID] = Task { [weak self] in
            try? await Task.sleep(for: quiet)
            guard !Task.isCancelled else { return }
            self?.writing.remove(documentID)
            self?.writingTimers[documentID] = nil
        }
    }

    // MARK: State

    private func state(_ id: Int64) -> FolderState? {
        folders.first { $0.id == id }
    }

    private func update(_ id: Int64, _ change: (inout FolderState) -> ()) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        change(&folders[index])
    }

    /// Replaces a document's row in its folder in place, or adds it when the folder doesn't list it yet.
    private func put(_ document: Document) {
        // Checked before update: even a no-op mutation of folders notifies observers.
        guard state(document.folderID)?.documents.first(where: { $0.id == document.id }) != document else { return }
        update(document.folderID) { state in
            if let index = state.documents.firstIndex(where: { $0.id == document.id }) {
                state.documents[index] = document
            } else {
                state.documents.append(document)
            }
        }
    }

    /// Rereads a folder's documents. For full rescans; single-row changes go through put.
    private func reloadDocuments(_ id: Int64) {
        let documents = (try? database.documents(folderID: id)) ?? []
        update(id) { $0.documents = documents }
    }

    var watcherCountForTesting: Int { watchers.count }

    /// Stops file events without forgetting the folders, so a test can change files as if DotMD were closed.
    func removeFolderWatchersForTesting() {
        for watcher in watchers.values { watcher.cancel() }
        watchers.removeAll()
    }
}
