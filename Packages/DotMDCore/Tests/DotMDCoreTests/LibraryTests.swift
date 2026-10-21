import Foundation
import Synchronization
import Testing
@testable import DotMDCore

/// Counts observation change notifications. The closure is Sendable, so the count goes through a Mutex.
private final class ChangeCounter: Sendable {
    private let value = Mutex(0)
    func increment() { value.withLock { $0 += 1 } }
    var count: Int { value.withLock { $0 } }
}

@MainActor
private func makeLibrary() throws -> Library {
    Library(database: try .inMemory())
}

@MainActor @Test func addingAFolderIndexesItsMarkdown() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("docs/plans/rollout.md", "# Rollout")
    try temp.write("node_modules/pkg/README.md", "# Dependency")
    try temp.write("main.swift", "print(1)")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let folder = try #require(library.folders.first)
    #expect(folder.url?.path == temp.url.path)
    #expect(Set(folder.documents.map(\.relativePath)) == ["README.md", "docs/plans/rollout.md"])
    #expect(folder.documents.allSatisfy { $0.readState == .read })
    #expect(folder.ignored == ["node_modules"])
    #expect(folder.unreadCount == 0)
}

@MainActor @Test func theLibraryReportsWhenStoredFoldersAreLoaded() async throws {
    let library = try makeLibrary()
    #expect(!library.hasLoaded)
    await library.start()
    #expect(library.hasLoaded)
    #expect(library.folders.isEmpty)
}

@MainActor @Test func addingTheSameFolderTwiceKeepsOne() async throws {
    let temp = try TempFolder()
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    try await library.addFolder(temp.url)
    #expect(library.folders.count == 1)
}

@MainActor @Test func newFilesAreNewAndBeingWritten() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    library.writingQuietPeriod = .seconds(1)
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    let file = try temp.write("HANDOFF.md", "# Handoff")
    await library.handle([file.path], in: id)
    let document = try #require(library.folders.first?.documents.first { $0.relativePath == "HANDOFF.md" })
    #expect(document.readState == .new)
    #expect(document.title == "Handoff")
    #expect(library.writing.contains(document.key))
    #expect(try await eventually { !library.writing.contains(document.key) })
}

@MainActor @Test func changedFilesStayChangedUntilRead() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    let file = try temp.write("README.md", "# Repo\n\nMore detail.")
    await library.handle([file.path], in: id)
    var document = try #require(library.folders.first?.documents.first)
    #expect(document.readState == .changed)
    #expect(library.folders.first?.unreadCount == 1)
    await library.markRead(document)
    document = try #require(library.folders.first?.documents.first)
    #expect(document.readState == .read)
    library.markUnread(document)
    #expect(library.folders.first?.documents.first?.readState == .new)
}

@MainActor @Test func deletedFilesLeaveTheList() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("old.md", "# Old")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    try temp.remove("old.md")
    await library.handle([temp.url.appending(path: "old.md").path], in: id)
    #expect(library.folders.first?.documents.map(\.relativePath) == ["README.md"])
}

@MainActor @Test func eventsInsideIgnoredFoldersAreSkipped() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    let file = try temp.write("node_modules/pkg/CHANGELOG.md", "# Changes")
    await library.handle([file.path], in: id)
    #expect(library.folders.first?.documents.map(\.relativePath) == ["README.md"])
}

@MainActor @Test func aNewFolderTriggersARescan() async throws {
    let temp = try TempFolder()
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    try temp.write("docs/specs/api.md", "# API")
    await library.handle([temp.url.appending(path: "docs").path], in: id)
    #expect(library.folders.first?.documents.map(\.relativePath) == ["docs/specs/api.md"])
}

@MainActor @Test func pinning() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let document = try #require(library.folders.first?.documents.first)
    library.setPinned(document, true)
    #expect(library.folders.first?.documents.first?.pinned == true)
}

@MainActor @Test func filesAreFoundByURL() async throws {
    let temp = try TempFolder()
    let file = try temp.write("docs/plan.md", "# Plan")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    #expect(library.document(at: file)?.relativePath == "docs/plan.md")
    #expect(library.folder(containing: file)?.url?.path == temp.url.path)
    let document = try #require(library.document(at: file))
    #expect(library.url(for: document)?.path == file.path)
}

@MainActor @Test func removingAFolderForgetsIt() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.removeFolder(id)
    #expect(library.folders.isEmpty)
}

@MainActor @Test func restartingFindsChangesMadeWhileClosed() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let database = try LibraryDatabase.inMemory()
    let first = Library(database: database)
    try await first.addFolder(temp.url)
    first.removeFolderWatchersForTesting()
    try temp.write("README.md", "# Repo, edited while DotMD was closed")
    let second = Library(database: database)
    await second.start()
    #expect(second.folders.first?.documents.first?.readState == .changed)
}

@MainActor @Test func colorsCanChange() async throws {
    let temp = try TempFolder()
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.setColor(.orange, for: id)
    #expect(library.folders.first?.folder.color == .orange)
}

@MainActor @Test func removingAFolderDeletesItsRow() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let database = try LibraryDatabase.inMemory()
    let first = Library(database: database)
    try await first.addFolder(temp.url)
    let id = try #require(first.folders.first?.id)
    first.removeFolder(id)
    let second = Library(database: database)
    await second.start()
    #expect(second.folders.isEmpty)
}

@MainActor @Test func removingAFolderWhileItsFirstScanRunsLeavesNoWatcher() async throws {
    let temp = try TempFolder()
    for index in 0..<500 {
        try temp.write("notes/\(index).md", "# Note \(index)")
    }
    let library = try makeLibrary()
    let adding = Task { try await library.addFolder(temp.url) }
    #expect(try await eventually { !library.folders.isEmpty })
    let id = try #require(library.folders.first?.id)
    library.removeFolder(id)
    try await adding.value
    #expect(library.folders.isEmpty)
    #expect(library.watcherCountForTesting == 0)
}

@MainActor @Test func aDeletedDottedFolderLeavesTheList() async throws {
    let temp = try TempFolder()
    let elsewhere = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("notes.archive/a.md", "# A")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.removeFolderWatchersForTesting()
    let archive = temp.url.appending(path: "notes.archive")
    try FileManager.default.moveItem(at: archive, to: elsewhere.url.appending(path: "notes.archive"))
    await library.handle([archive.path], in: id)
    #expect(library.folders.first?.documents.map(\.relativePath) == ["README.md"])
}

@MainActor @Test func showingIgnoredPathsListsThemAndHidingThemAgainDoesNot() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("node_modules/pkg/README.md", "# Dependency")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let listsDependency = { library.folders.first?.documents.contains { $0.relativePath == "node_modules/pkg/README.md" } == true }
    library.showIgnored = true
    #expect(try await eventually(listsDependency))
    library.showIgnored = false
    #expect(try await eventually { !listsDependency() })
}

/// A file event that arrives while the first scan runs waits for it, so the scan can't overwrite the newer content.
@MainActor @Test func aFileEventDuringTheFirstScanAppliesAfterIt() async throws {
    let temp = try TempFolder()
    for index in 0..<500 {
        try temp.write("notes/\(index).md", "# Note \(index)")
    }
    let file = try temp.write("plan.md", "# One")
    let library = try makeLibrary()
    let adding = Task { try await library.addFolder(temp.url) }
    // The folder shows up once the first scan is queued.
    #expect(try await eventually { !library.folders.isEmpty })
    let id = try #require(library.folders.first?.id)
    try temp.write("plan.md", "# Two")
    await library.handle([file.path], in: id)
    #expect(library.folders.first?.documents.count == 501)
    #expect(library.folders.first?.documents.first { $0.relativePath == "plan.md" }?.title == "Two")
    try await adding.value
    #expect(library.folders.first?.documents.first { $0.relativePath == "plan.md" }?.title == "Two")
}

@MainActor @Test func reconnectingKeepsReadState() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("plan.md", "# Plan")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    let plan = try #require(library.folders.first?.documents.first { $0.relativePath == "plan.md" })
    library.markUnread(plan)
    let before = Dictionary(uniqueKeysWithValues: (library.folders.first?.documents ?? []).map { ($0.relativePath, $0.readState) })
    library.removeFolderWatchersForTesting()
    try await library.reconnect(id, to: temp.url)
    let after = Dictionary(uniqueKeysWithValues: (library.folders.first?.documents ?? []).map { ($0.relativePath, $0.readState) })
    #expect(after == before)
    #expect(after["plan.md"] == .new)
    #expect(library.folders.first?.accessLost == false)
    #expect(library.watcherCountForTesting == 1)
}

@MainActor @Test func anEventForARemovedRootLosesAccess() async throws {
    let temp = try TempFolder()
    let elsewhere = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    try FileManager.default.moveItem(at: temp.url, to: elsewhere.url.appending(path: "moved"))
    await library.handle([temp.url.path], in: id)
    #expect(library.folders.first?.accessLost == true)
    #expect(library.folders.first?.documents.map(\.relativePath) == ["README.md"])
    #expect(library.watcherCountForTesting == 0)
}

@MainActor @Test func droppedEventsRescanTheFolder() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.removeFolderWatchersForTesting()
    try temp.write("docs/new.md", "# New")
    await library.handle([FolderEvent(path: temp.url.path, isDirectory: false, isRemoved: false, isRenamed: false, mustScanSubDirs: true)], in: id)
    #expect(Set(library.folders.first?.documents.map(\.relativePath) ?? []) == ["README.md", "docs/new.md"])
}

/// Read state per path, to compare a folder's rows before and after.
@MainActor
private func readStates(_ library: Library) -> [String: ReadState] {
    Dictionary(uniqueKeysWithValues: (library.folders.first?.documents ?? []).map { ($0.relativePath, $0.readState) })
}

@MainActor @Test func aRescanOfAVanishedRootKeepsTheRows() async throws {
    let temp = try TempFolder()
    let elsewhere = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("plan.md", "# Plan")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    library.removeFolderWatchersForTesting()
    // Batches already handed to the main actor run now, before the move, so only the rescan can see the missing root.
    try await Task.sleep(for: .milliseconds(100))
    library.markUnread(try #require(library.folders.first?.documents.first { $0.relativePath == "plan.md" }))
    let before = readStates(library)
    try FileManager.default.moveItem(at: temp.url, to: elsewhere.url.appending(path: "moved"))
    library.showIgnored = true
    #expect(try await eventually { library.folders.first?.accessLost == true })
    #expect(readStates(library) == before)
    #expect(before["plan.md"] == .new)
}

@MainActor @Test func filesThatVanishWithTheRootKeepTheirRows() async throws {
    let temp = try TempFolder()
    let elsewhere = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("plan.md", "# Plan")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.removeFolderWatchersForTesting()
    let before = readStates(library)
    let paths = ["README.md", "plan.md"].map { temp.url.appending(path: $0).path }
    try FileManager.default.moveItem(at: temp.url, to: elsewhere.url.appending(path: "moved"))
    await library.handle(paths.map { FolderEvent(path: $0, isDirectory: false, isRemoved: true, isRenamed: false) }, in: id)
    #expect(library.folders.first?.accessLost == true)
    #expect(readStates(library) == before)
}

/// Every stored folder is resolved before any scan starts, so a folder waiting for its scan reads as ready.
@MainActor @Test func foldersWaitingForTheirScanAreNotAccessLost() async throws {
    let first = try TempFolder()
    let second = try TempFolder()
    for index in 0..<300 {
        try first.write("notes/\(index).md", "# Note \(index)")
        try second.write("notes/\(index).md", "# Note \(index)")
    }
    let database = try LibraryDatabase.inMemory()
    let adding = Library(database: database)
    try await adding.addFolder(first.url)
    try await adding.addFolder(second.url)
    adding.removeFolderWatchersForTesting()
    let library = Library(database: database)
    let starting = Task { await library.start() }
    #expect(try await eventually { !library.folders.isEmpty })
    #expect(library.folders.map(\.status) == [.ready, .ready])
    #expect(library.folders.allSatisfy { !$0.accessLost && !$0.isConnecting && $0.url != nil })
    await starting.value
    #expect(library.folders.map(\.status) == [.ready, .ready])
}

/// DotMD quit after adding a folder and before its first scan wrote anything. The next launch's scan is the first.
@MainActor @Test func anInterruptedFirstScanStillCountsEverythingAsRead() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("docs/plan.md", "# Plan")
    let database = try LibraryDatabase.inMemory()
    _ = try database.insert(WatchedFolder(bookmark: FolderAccess.bookmark(for: temp.url), path: temp.url.path, name: "repo", color: .blue))
    let library = Library(database: database)
    await library.start()
    let folder = try #require(library.folders.first)
    #expect(folder.documents.count == 2)
    #expect(folder.unreadCount == 0)
    #expect(folder.folder.indexedAt != nil)
}

@MainActor @Test func anUnreadableRootKeepsEveryRow() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("plan.md", "# Plan")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.removeFolderWatchersForTesting()
    library.markUnread(try #require(library.folders.first?.documents.first { $0.relativePath == "plan.md" }))
    let before = readStates(library)
    try setPermissions(temp.url, 0o000)
    defer { try? setPermissions(temp.url, 0o755) }
    await library.handle([FolderEvent(path: temp.url.path, isDirectory: true, isRemoved: false, isRenamed: false, mustScanSubDirs: true)], in: id)
    #expect(readStates(library) == before)
    // Inside an unreadable root a file can't even be checked for, which is not the same as being gone.
    await library.handle([temp.url.appending(path: "plan.md").path], in: id)
    #expect(readStates(library) == before)
    #expect(library.folders.first?.status == .ready)
}

/// The first scan can't read the root, so it writes nothing and the folder's next scan still counts as first.
@MainActor @Test func aFailedFirstScanLeavesTheNextOneFirst() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let database = try LibraryDatabase.inMemory()
    _ = try database.insert(WatchedFolder(bookmark: FolderAccess.bookmark(for: temp.url), path: temp.url.path, name: "repo", color: .blue))
    try setPermissions(temp.url, 0o000)
    defer { try? setPermissions(temp.url, 0o755) }
    let library = Library(database: database)
    await library.start()
    let id = try #require(library.folders.first?.id)
    library.removeFolderWatchersForTesting()
    #expect(library.folders.first?.status == .ready)
    #expect(library.folders.first?.documents.isEmpty == true)
    #expect(library.folders.first?.folder.indexedAt == nil)
    try setPermissions(temp.url, 0o755)
    await library.handle([FolderEvent(path: temp.url.path, isDirectory: true, isRemoved: false, isRenamed: false, mustScanSubDirs: true)], in: id)
    #expect(library.folders.first?.documents.map(\.readState) == [.read])
    #expect(library.folders.first?.folder.indexedAt != nil)
}

@MainActor @Test func anUnreadableFileKeepsItsRow() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let plan = try temp.write("plan.md", "# Plan")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.removeFolderWatchersForTesting()
    let before = readStates(library)
    try setPermissions(plan, 0o000)
    defer { try? setPermissions(plan, 0o644) }
    await library.handle([plan.path], in: id)
    #expect(readStates(library) == before)
    await library.handle([FolderEvent(path: temp.url.path, isDirectory: true, isRemoved: false, isRenamed: false, mustScanSubDirs: true)], in: id)
    #expect(readStates(library) == before)
}

@MainActor @Test func aBigBatchOfFilesRescansOnce() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.removeFolderWatchersForTesting()
    let paths = try (0..<60).map { try temp.write("notes/\($0).md", "# Note \($0)").path }
    await library.handle(paths.map { FolderEvent(path: $0, isDirectory: false, isRemoved: false, isRenamed: false) }, in: id)
    #expect(library.folders.first?.documents.count == 61)
    #expect(library.folders.first?.unreadCount == 60)
}

@MainActor @Test func showingAndHidingIgnoredPathsAddsNoUnreadFiles() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("node_modules/pkg/README.md", "# Dependency")
    try temp.write(".git/HEAD", "ref: refs/heads/main\n")
    try temp.write(".git/notes.md", "# Not a document")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let listsDependency = { library.folders.first?.documents.contains { $0.relativePath == "node_modules/pkg/README.md" } == true }
    library.showIgnored = true
    #expect(try await eventually(listsDependency))
    #expect(library.folders.first?.unreadCount == 0)
    #expect(library.folders.first?.documents.contains { $0.relativePath.hasPrefix(".git/") } == false)
    library.showIgnored = false
    #expect(try await eventually { !listsDependency() })
    #expect(library.folders.first?.unreadCount == 0)
    #expect(library.folders.first?.ignored == ["node_modules"])
}

/// An event can add a row under an ignored folder while ignored paths are shown, before the rescan gets there.
@MainActor @Test func anEventUnderAnIgnoredFolderWhileShownArrivesRead() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.removeFolderWatchersForTesting()
    library.showIgnored = true
    let dependency = try temp.write("node_modules/pkg/README.md", "# Dependency")
    let docs = try temp.write("docs/new.md", "# New")
    await library.handle([dependency.path, docs.path], in: id)
    let states = readStates(library)
    #expect(states["node_modules/pkg/README.md"] == .read)
    #expect(states["docs/new.md"] == .new)
}

/// An event for a file whose row is unchanged leaves the list as is, so the list doesn't redraw on every write.
@MainActor @Test func anUnchangedFileLeavesTheListAsIs() async throws {
    let temp = try TempFolder()
    let readme = try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.removeFolderWatchersForTesting()
    let before = library.folders
    let changes = ChangeCounter()
    withObservationTracking {
        _ = library.folders
    } onChange: {
        changes.increment()
    }
    await library.handle([readme.path], in: id)
    #expect(library.folders == before)
    #expect(changes.count == 0)
}

@MainActor @Test func pausedWatchingCatchesUpWhenItEnds() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.pauseWatching(for: .seconds(3600))
    #expect(library.pausedUntil != nil)
    let file = try temp.write("HANDOFF.md", "# Handoff")
    await library.handle([file.path], in: id)
    #expect(library.folders.first?.documents.contains { $0.relativePath == "HANDOFF.md" } == false)
    await library.resumeWatching()
    #expect(library.pausedUntil == nil)
    #expect(library.folders.first?.documents.contains { $0.relativePath == "HANDOFF.md" } == true)
}

@MainActor @Test func pausingEndsOnItsOwn() async throws {
    let library = try makeLibrary()
    library.pauseWatching(for: .milliseconds(200))
    #expect(try await eventually { library.pausedUntil == nil })
}
