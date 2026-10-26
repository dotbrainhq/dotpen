import Foundation

/// A throwaway folder under the temp directory. url is the real path: the temp directory sits behind a /var symlink,
/// and file events report /private/var.
struct TempFolder {
    let url: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "dotpen-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let real = realpath(base.path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        }
        url = URL(fileURLWithPath: real ?? base.path, isDirectory: true)
    }

    @discardableResult
    func write(_ relativePath: String, _ text: String) throws -> URL {
        let file = url.appending(path: relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func remove(_ relativePath: String) throws {
        try FileManager.default.removeItem(at: url.appending(path: relativePath))
    }
}

/// Polls until the condition holds or the deadline passes, then returns whether it held. Runs on the caller's actor.
func eventually(
    within deadline: Duration = .seconds(5),
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () -> Bool
) async throws -> Bool {
    let end = ContinuousClock.now + deadline
    while !condition() {
        guard ContinuousClock.now < end else { return false }
        try await Task.sleep(for: .milliseconds(20))
    }
    return true
}

/// Sets a path's permission bits, for tests that need something dotPen can't read.
func setPermissions(_ url: URL, _ mode: Int) throws {
    try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
}
