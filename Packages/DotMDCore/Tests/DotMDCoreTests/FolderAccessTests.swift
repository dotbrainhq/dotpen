import Foundation
import Synchronization
import Testing
@testable import DotMDCore

/// Collects events from the watcher's queue.
private final class EventLog: Sendable {
    let events = Mutex<[FolderEvent]>([])
    var all: [FolderEvent] { events.withLock { $0 } }
}

@Test func bookmarksResolveToTheSameFolder() throws {
    let temp = try TempFolder()
    let bookmark = try FolderAccess.bookmark(for: temp.url)
    let resolved = try FolderAccess.resolve(bookmark)
    defer { FolderAccess.stop(resolved.url) }
    #expect(FolderAccess.canonical(resolved.url).path == temp.url.path)
}

@Test func canonicalPathsFollowSymlinks() {
    #expect(FolderAccess.canonical(URL(fileURLWithPath: "/var")).path == "/private/var")
}

@Test func watcherReportsNewAndDeletedFiles() async throws {
    let temp = try TempFolder()
    let log = EventLog()
    let watcher = FolderWatcher(url: temp.url) { events in log.events.withLock { $0 += events } }
    defer { watcher.cancel() }
    let notes = temp.url.appending(path: "notes.md").path
    try await Task.sleep(for: .milliseconds(300))
    try temp.write("notes.md", "# Notes")
    try await Task.sleep(for: .seconds(1))
    #expect(log.all.contains { $0.path == notes && !$0.isDirectory })
    log.events.withLock { $0.removeAll() }
    try temp.remove("notes.md")
    try await Task.sleep(for: .seconds(1))
    #expect(log.all.contains { $0.path == notes && $0.isRemoved })
}

@Test func watcherFlagsFolders() async throws {
    let temp = try TempFolder()
    let log = EventLog()
    let watcher = FolderWatcher(url: temp.url) { events in log.events.withLock { $0 += events } }
    defer { watcher.cancel() }
    try await Task.sleep(for: .milliseconds(300))
    try FileManager.default.createDirectory(at: temp.url.appending(path: "v1.2"), withIntermediateDirectories: false)
    try await Task.sleep(for: .seconds(1))
    #expect(log.all.contains { $0.path == temp.url.appending(path: "v1.2").path && $0.isDirectory })
}

private final class WatcherBox: Sendable {
    let watcher = Mutex<FolderWatcher?>(nil)
    let calls = Mutex<Int>(0)
}

// The deinit-on-queue path isn't tested directly: dropping the last reference inside onChange can't be made deterministic.
@Test func watcherCanCancelItselfFromItsCallback() async throws {
    let temp = try TempFolder()
    let box = WatcherBox()
    let watcher = FolderWatcher(url: temp.url) { _ in
        box.calls.withLock { $0 += 1 }
        box.watcher.withLock { $0 }?.cancel()
    }
    box.watcher.withLock { $0 = watcher }
    try await Task.sleep(for: .milliseconds(300))
    try temp.write("first.md", "# First")
    try await Task.sleep(for: .milliseconds(600))
    try temp.write("second.md", "# Second")
    try await Task.sleep(for: .seconds(1))
    #expect(box.calls.withLock { $0 } == 1)
    watcher.cancel()
}
