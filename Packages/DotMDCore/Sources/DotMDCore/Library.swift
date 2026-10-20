import Foundation
import Observation

/// One watched folder as the file list shows it.
public struct FolderState: Identifiable, Equatable, Sendable {
    public var folder: WatchedFolder
    /// The folder's real location while DotMD can read it. Nil when access was lost.
    public var url: URL?
    public var branch: String?
    public var documents: [Document]
    /// Paths hidden by ignore rules, relative to the folder.
    public var ignored: [String]

    public var id: Int64 { folder.id ?? 0 }
    public var accessLost: Bool { url == nil }
    public var unreadCount: Int { documents.filter { $0.readState != .read }.count }
}

/// Watched folders and their Markdown, kept current as files change. Lives on the main actor for SwiftUI;
/// scanning and hashing run on background tasks.
@MainActor
@Observable
public final class Library {
    public private(set) var folders: [FolderState] = []
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
    /// How long a file counts as being written after its last change.
    @ObservationIgnored public var writingQuietPeriod: Duration = .seconds(3)

    @ObservationIgnored private let database: LibraryDatabase
    @ObservationIgnored private var watchers: [Int64: FolderWatcher] = [:]
    @ObservationIgnored private var writingTimers: [Int64: Task<(), Never>] = [:]
    @ObservationIgnored private var started = false
    /// The URL each folder's security-scoped access was started on. Paths use the canonical root instead.
    @ObservationIgnored private var accessURLs: [Int64: URL] = [:]
    /// The newest job per folder. Scans and event batches for one folder run one after another.
    @ObservationIgnored private var folderWork: [Int64: Task<(), Never>] = [:]
    @ObservationIgnored private var rescanAllTask: Task<(), Never>?
    /// A queued rescan per folder that hasn't started yet. Later requests wait on it instead of queuing another.
    @ObservationIgnored private var pendingRescans: [Int64: Task<(), Never>] = [:]

    public init(database: LibraryDatabase) {
        self.database = database
    }

    // MARK: Folders

    /// Opens every stored folder, indexes it, and starts watching. Calling it again does nothing.
    public func start() async {
        guard !started else { return }
        started = true
        let stored = (try? database.folders()) ?? []
        folders = stored.map { folder in
            FolderState(folder: folder, url: nil, branch: nil, documents: (try? database.documents(folderID: folder.id ?? 0)) ?? [], ignored: [])
        }
        for folder in stored {
            await open(folder, firstScan: false)
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
        folders.append(FolderState(folder: folder, url: nil, branch: nil, documents: [], ignored: []))
        await open(folder, firstScan: true)
    }

    /// Points a folder whose access was lost at the location the person chose again. Read state is kept.
    public func reconnect(_ id: Int64, to url: URL) async throws {
        guard var folder = state(id)?.folder else { return }
        folder.bookmark = try FolderAccess.bookmark(for: url)
        folder.path = FolderAccess.canonical(url).path
        try database.update(folder)
        await open(folder, firstScan: false)
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

    public func markRead(_ document: Document) {
        _ = try? database.markRead(documentID: document.key)
        reloadDocuments(document.folderID)
    }

    public func markUnread(_ document: Document) {
        _ = try? database.markUnread(documentID: document.key)
        reloadDocuments(document.folderID)
    }

    public func setPinned(_ document: Document, _ pinned: Bool) {
        _ = try? database.setPinned(documentID: document.key, pinned)
        reloadDocuments(document.folderID)
    }

    // MARK: Indexing

    /// Resolves the folder's bookmark, starts watching, then scans. The watcher starts first so changes made during
    /// the scan aren't lost: their batches queue behind the scan and apply after it.
    private func open(_ folder: WatchedFolder, firstScan: Bool) async {
        guard let id = folder.id else { return }
        watchers.removeValue(forKey: id)?.cancel()
        // The new access starts before the old one stops, so the folder is never left without a grant in between.
        let resolved = try? FolderAccess.resolve(folder.bookmark)
        releaseAccess(id)
        guard let resolved else {
            update(id) { $0.url = nil }
            return
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
        }
        watchers[id] = FolderWatcher(url: root) { [weak self] events in
            Task { @MainActor [weak self] in await self?.handle(events, in: id) }
        }
        await rescan(id, firstScan: firstScan)
        if state(id) == nil {
            // Removed while the scan ran. removeFolder already let go of both; this keeps a late open from holding them.
            watchers.removeValue(forKey: id)?.cancel()
            releaseAccess(id)
        }
    }

    private func releaseAccess(_ id: Int64) {
        if let url = accessURLs.removeValue(forKey: id) { FolderAccess.stop(url) }
    }

    /// The folder's root went away: keep its rows and read state, show it as needing reconnection.
    private func loseAccess(_ id: Int64) {
        watchers.removeValue(forKey: id)?.cancel()
        releaseAccess(id)
        update(id) { $0.url = nil }
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
            await rescan(id, firstScan: false)
        }
    }

    /// Queues a rescan and returns once it has run. A later rescan that is queued and not started yet already covers
    /// this request, so it waits on that one. A first scan is never merged: it marks every file as read.
    private func rescan(_ id: Int64, firstScan: Bool) async {
        if !firstScan, let pending = pendingRescans[id] {
            await pending.value
            return
        }
        let task = enqueue(id) { [weak self] in
            if !firstScan { self?.pendingRescans[id] = nil }
            await self?.performRescan(id, firstScan: firstScan)
        }
        if !firstScan { pendingRescans[id] = task }
        await task.value
        if folderWork[id] == task { folderWork[id] = nil }
    }

    private func performRescan(_ id: Int64, firstScan: Bool) async {
        guard let root = state(id)?.url else { return }
        let rules = showIgnored ? IgnoreRules.none : IgnoreRules.load(root: root)
        let result = await Task.detached(priority: .utility) { FolderScanner.scan(root: root, rules: rules) }.value
        // Removed or reconnected elsewhere while scanning: these results belong to nothing now.
        guard state(id)?.url == root else { return }
        // A vanished root scans as empty. Writing that would delete every row and its read state.
        guard FileManager.default.fileExists(atPath: root.path) else {
            loseAccess(id)
            return
        }
        try? database.replaceDocuments(folderID: id, with: result.files)
        let branch = GitBranch.current(in: root)
        update(id) { state in
            state.ignored = result.ignored
            state.branch = branch
        }
        reloadDocuments(id)
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
        var needsRescan = false
        await serialized(id) { [weak self] in needsRescan = await self?.apply(events, in: id) ?? false }
        if needsRescan { await rescan(id, firstScan: false) }
    }

    /// Returns true when the folder needs a full rescan: a folder event outside the ignore rules, the root .gitignore,
    /// or a batch where FSEvents dropped or merged events. Otherwise a Markdown file updates its own row and other
    /// files are skipped, except .git/HEAD (branch). The root going away loses access.
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
            if relativePath == ".git" || relativePath.hasPrefix(".git/") || rules.containsIgnoredPath(relativePath) { continue }
            if event.isDirectory {
                needsRescan = true
            } else if FolderScanner.isMarkdown(URL(fileURLWithPath: path)) {
                files.insert(relativePath)
            }
        }
        if needsRescan { return true }
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
                try? database.deleteDocument(folderID: id, relativePath: relativePath)
                continue
            }
            let before = try? database.document(folderID: id, relativePath: relativePath)
            if let stored = try? database.upsert(file, folderID: id), before?.contentHash != stored.contentHash {
                markWriting(stored.key)
            }
        }
        reloadDocuments(id)
        return false
    }

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
