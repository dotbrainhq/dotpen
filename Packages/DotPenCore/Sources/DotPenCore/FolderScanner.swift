import CryptoKit
import Foundation

public struct ScanResult: Sendable {
    public var files: [ScannedFile]
    /// Folders and Markdown files hidden by ignore rules, relative to the root. A hidden folder counts once.
    /// .git is never listed: it is always skipped.
    public var ignored: [String]
    /// Markdown files that exist but couldn't be read, relative to the root. Their stored rows should stay.
    public var unreadable: [String]
}

/// Walks a folder for Markdown files.
public enum FolderScanner {
    /// MDX is Markdown with components, and .mdc is Cursor's rule format: Markdown with front matter.
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mdx", "mdc"]

    public static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    /// Every Markdown file under root that the rules don't hide, with title, kind and hash, sorted by path.
    /// Nil when root can't be read as a folder, so a read failure is never mistaken for an empty folder.
    public static func scan(root: URL, rules: IgnoreRules) -> ScanResult? {
        var files: [ScannedFile] = []
        var unreadable: [String] = []
        let ignored = walk(root: root, rules: rules) { url, relativePath in
            if let file = summarize(fileURL: url, relativePath: relativePath) {
                files.append(file)
            } else if !isGone(url.path) {
                unreadable.append(relativePath)
            }
        }
        guard let ignored else { return nil }
        return ScanResult(files: files.sorted { $0.relativePath < $1.relativePath }, ignored: ignored, unreadable: unreadable.sorted())
    }

    /// Counts Markdown files without reading them. First launch uses this to size up folders. 0 when root can't be read.
    public static func countMarkdown(root: URL, rules: IgnoreRules) -> Int {
        var count = 0
        _ = walk(root: root, rules: rules) { _, _ in count += 1 }
        return count
    }

    /// True only when nothing is at path. Unlike fileExists(atPath:), a path that can't be checked, such as one
    /// inside a folder dotPen can't read, doesn't count as gone.
    static func isGone(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) != 0 else { return false }
        return errno == ENOENT || errno == ENOTDIR
    }

    public static func summarize(fileURL: URL, relativePath: String) -> ScannedFile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
        return ScannedFile(
            relativePath: relativePath,
            title: MarkdownSummary.title(in: String(decoding: data, as: UTF8.self)),
            kind: .detect(relativePath: relativePath),
            contentHash: Snapshots.hash(data),
            modifiedAt: modified,
            content: data
        )
    }

    /// Calls visit for each Markdown file and returns the ignored folders and Markdown files, or nil when root
    /// can't be listed. Symbolic links and .git folders are skipped.
    private static func walk(root: URL, rules: IgnoreRules, visit: (URL, String) -> ()) -> [String]? {
        let root = Paths.canonical(root)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard (try? FileManager.default.contentsOfDirectory(atPath: root.path)) != nil,
              let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else {
            return nil
        }
        let rootPath = root.path
        var ignored: [String] = []
        for case let url as URL in enumerator {
            let path = url.path
            guard path.hasPrefix(rootPath + "/") else { continue }
            let relativePath = String(path.dropFirst(rootPath.count + 1))
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true { continue }
            let isDirectory = values?.isDirectory == true
            // Never worth showing, even with ignored paths shown.
            if isDirectory && url.lastPathComponent == ".git" {
                enumerator.skipDescendants()
                continue
            }
            if rules.isIgnored(relativePath, isDirectory: isDirectory) {
                if isDirectory || isMarkdown(url) { ignored.append(relativePath) }
                if isDirectory { enumerator.skipDescendants() }
                continue
            }
            if !isDirectory && isMarkdown(url) { visit(url, relativePath) }
        }
        return ignored
    }
}
