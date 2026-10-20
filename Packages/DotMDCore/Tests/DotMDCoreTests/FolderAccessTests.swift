import Foundation
import Synchronization
import Testing
@testable import DotMDCore

/// Collects paths from the watcher's queue.
private final class PathLog: Sendable {
    let paths = Mutex<[String]>([])
    var all: [String] { paths.withLock { $0 } }
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
    let log = PathLog()
    let watcher = FolderWatcher(url: temp.url) { paths in log.paths.withLock { $0 += paths } }
    defer { watcher.cancel() }
    try await Task.sleep(for: .milliseconds(300))
    try temp.write("notes.md", "# Notes")
    try await Task.sleep(for: .seconds(1))
    #expect(log.all.contains(temp.url.appending(path: "notes.md").path))
    log.paths.withLock { $0.removeAll() }
    try temp.remove("notes.md")
    try await Task.sleep(for: .seconds(1))
    #expect(log.all.contains(temp.url.appending(path: "notes.md").path))
}

private final class WatcherBox: Sendable {
    let watcher = Mutex<FolderWatcher?>(nil)
}

@Test func watcherCanCancelItselfFromItsCallback() async throws {
    let temp = try TempFolder()
    let log = PathLog()
    let box = WatcherBox()
    let watcher = FolderWatcher(url: temp.url) { paths in
        log.paths.withLock { $0 += paths }
        box.watcher.withLock { $0 }?.cancel()
    }
    box.watcher.withLock { $0 = watcher }
    try await Task.sleep(for: .milliseconds(300))
    try temp.write("notes.md", "# Notes")
    try await Task.sleep(for: .seconds(1))
    let path = temp.url.appending(path: "notes.md").path
    #expect(log.all.filter { $0 == path }.count == 1)
    watcher.cancel()
}
