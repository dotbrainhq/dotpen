import Foundation

/// A throwaway folder under the temp directory. url is the real path: the temp directory sits behind a /var symlink,
/// and file events report /private/var.
struct TempFolder {
    let url: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "dotmd-tests-\(UUID().uuidString)")
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
