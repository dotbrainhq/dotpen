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
    /// Shows paths the ignore rules would hide. Changing it rescans every folder.
    public var showIgnored = false {
        didSet {
            if showIgnored != oldValue { Task { await rescanAll() } }
        }
    }
    /// How long a file counts as being written after its last change.
    @ObservationIgnored public var writingQuietPeriod: Duration = .seconds(3)

    @ObservationIgnored private let database: LibraryDatabase
    @ObservationIgnored private var watchers: [Int64: FolderWatcher] = [:]
    @ObservationIgnored private var writingTimers: [Int64: Task<(), Never>] = [:]
    @ObservationIgnored private var started = false

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

    /// Watches a folder the person chose. Adding a folder that is already watched does nothing.
    public func addFolder(_ url: URL) async throws {
        let root = FolderAccess.canonical(url)
        guard !folders.contains(where: { $0.folder.path == root.path }) else { return }
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
        if let url = state(id)?.url { FolderAccess.stop(url) }
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
        try? database.markRead(documentID: document.key)
        reloadDocuments(document.folderID)
    }

    public func markUnread(_ document: Document) {
        try? database.markUnread(documentID: document.key)
        reloadDocuments(document.folderID)
    }

    public func setPinned(_ document: Document, _ pinned: Bool) {
        try? database.setPinned(documentID: document.key, pinned)
        reloadDocuments(document.folderID)
    }

    // MARK: Indexing

    private func open(_ folder: WatchedFolder, firstScan: Bool) async {
        guard let id = folder.id else { return }
        watchers.removeValue(forKey: id)?.cancel()
        guard let resolved = try? FolderAccess.resolve(folder.bookmark) else {
            update(id) { $0.url = nil }
            return
        }
        var folder = folder
        let root = FolderAccess.canonical(resolved.url)
        if let fresh = resolved.refreshedBookmark { folder.bookmark = fresh }
        folder.path = root.path
        try? database.update(folder)
        update(id) { state in
            state.folder = folder
            state.url = root
        }
        await rescan(id, firstScan: firstScan)
        watchers[id] = FolderWatcher(url: root) { [weak self] paths in
            Task { @MainActor [weak self] in await self?.handle(paths, in: id) }
        }
    }

    private func rescanAll() async {
        for folder in folders {
            await rescan(folder.id, firstScan: false)
        }
    }

    private func rescan(_ id: Int64, firstScan: Bool) async {
        guard let root = state(id)?.url else { return }
        let rules = showIgnored ? IgnoreRules.none : IgnoreRules.load(root: root)
        let result = await Task.detached(priority: .utility) { FolderScanner.scan(root: root, rules: rules) }.value
        try? database.replaceDocuments(folderID: id, with: result.files, firstScan: firstScan)
        let branch = GitBranch.current(in: root)
        update(id) { state in
            state.ignored = result.ignored
            state.branch = branch
        }
        reloadDocuments(id)
    }

    /// Applies file events for one folder. A Markdown file updates its own row. A folder that appeared,
    /// moved or went away, or a changed .gitignore, rescans the whole folder.
    func handle(_ paths: [String], in id: Int64) async {
        guard let root = state(id)?.url else { return }
        let rules = showIgnored ? IgnoreRules.none : IgnoreRules.load(root: root)
        var files: [String] = []
        var needsRescan = false
        for path in Set(paths) {
            guard path.hasPrefix(root.path + "/") else { continue }
            let relativePath = String(path.dropFirst(root.path.count + 1))
            if relativePath == ".git/HEAD" {
                let branch = GitBranch.current(in: root)
                update(id) { $0.branch = branch }
                continue
            }
            if relativePath.hasPrefix(".git/") || rules.containsIgnoredPath(relativePath) { continue }
            if relativePath == ".gitignore" {
                needsRescan = true
                continue
            }
            let url = root.appending(path: relativePath)
            if FolderScanner.isMarkdown(url) {
                files.append(relativePath)
                continue
            }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue || (!exists && url.pathExtension.isEmpty) { needsRescan = true }
        }
        if needsRescan {
            await rescan(id, firstScan: false)
            return
        }
        guard !files.isEmpty else { return }
        for relativePath in files {
            let url = root.appending(path: relativePath)
            let file = await Task.detached(priority: .utility) { FolderScanner.summarize(fileURL: url, relativePath: relativePath) }.value
            guard let file else {
                try? database.deleteDocument(folderID: id, relativePath: relativePath)
                continue
            }
            let before = try? database.document(folderID: id, relativePath: relativePath)
            if let stored = try? database.upsert(file, folderID: id), before?.contentHash != stored.contentHash {
                markWriting(stored.key)
            }
        }
        reloadDocuments(id)
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

    /// Stops file events without forgetting the folders, so a test can change files as if DotMD were closed.
    func removeFolderWatchersForTesting() {
        for watcher in watchers.values { watcher.cancel() }
        watchers.removeAll()
    }
}
