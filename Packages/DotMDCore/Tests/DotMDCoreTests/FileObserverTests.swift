import Foundation
import Synchronization
import Testing
@testable import DotMDCore

private func tempFile(_ text: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "dotmd-\(UUID().uuidString).md")
    try text.write(to: url, atomically: false, encoding: .utf8)
    return url
}

private func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
    try handle.close()
}

/// Mutex can't be copied or captured by an escaping closure, so the tests share it through a class.
private final class Counter: Sendable {
    private let value = Mutex(0)
    func increment() { value.withLock { $0 += 1 } }
    var count: Int { value.withLock { $0 } }
}

private func waitFor(_ counter: Counter, atLeast target: Int, timeout: Duration = .seconds(3)) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while counter.count < target {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

@Test func reportsInPlaceWrites() async throws {
    let url = try tempFile("one")
    let count = Counter()
    let observer = FileObserver(url: url) { count.increment() }
    defer { observer.cancel() }
    try await Task.sleep(for: .milliseconds(100))
    try append(" two", to: url)
    #expect(await waitFor(count, atLeast: 1))
}

@Test func survivesAtomicSaves() async throws {
    let url = try tempFile("one")
    let count = Counter()
    let observer = FileObserver(url: url) { count.increment() }
    defer { observer.cancel() }
    try await Task.sleep(for: .milliseconds(100))
    try "two".write(to: url, atomically: true, encoding: .utf8)
    #expect(await waitFor(count, atLeast: 1))
    try await Task.sleep(for: .milliseconds(300))
    try "three".write(to: url, atomically: true, encoding: .utf8)
    #expect(await waitFor(count, atLeast: 2))
}

@Test func coalescesBursts() async throws {
    let url = try tempFile("start")
    let count = Counter()
    let observer = FileObserver(url: url, debounce: .milliseconds(150)) { count.increment() }
    defer { observer.cancel() }
    try await Task.sleep(for: .milliseconds(100))
    for i in 0..<5 {
        try append(" \(i)", to: url)
    }
    #expect(await waitFor(count, atLeast: 1))
    try await Task.sleep(for: .milliseconds(400))
    #expect(count.count == 1)
}
