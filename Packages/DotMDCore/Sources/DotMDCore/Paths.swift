import Darwin
import Foundation

enum Paths {
    /// The real path of a URL with symlinks resolved. Unlike resolvingSymlinksInPath, it keeps /private/var as is,
    /// which is the form file events report.
    static func canonical(_ url: URL) -> URL {
        let real = realpath(url.path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        }
        guard let real else { return url.standardizedFileURL }
        return URL(fileURLWithPath: real, isDirectory: url.hasDirectoryPath)
    }
}
