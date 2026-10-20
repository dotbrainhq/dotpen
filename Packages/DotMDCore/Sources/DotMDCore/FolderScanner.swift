import CryptoKit
import Foundation

public struct ScanResult: Sendable {
    public var files: [ScannedFile]
    /// Folders and Markdown files hidden by ignore rules, relative to the root. A hidden folder counts once.
    public var ignored: [String]
}

/// Walks a folder for Markdown files.
public enum FolderScanner {
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown"]

    public static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    /// Every Markdown file under root that the rules don't hide, with title, kind and hash, sorted by path.
    public static func scan(root: URL, rules: IgnoreRules) -> ScanResult {
        var files: [ScannedFile] = []
        let ignored = walk(root: root, rules: rules) { url, relativePath in
            if let file = summarize(fileURL: url, relativePath: relativePath) { files.append(file) }
        }
        return ScanResult(files: files.sorted { $0.relativePath < $1.relativePath }, ignored: ignored)
    }

    /// Counts Markdown files without reading them. First launch uses this to size up folders.
    public static func countMarkdown(root: URL, rules: IgnoreRules) -> Int {
        var count = 0
        _ = walk(root: root, rules: rules) { _, _ in count += 1 }
        return count
    }

    public static func summarize(fileURL: URL, relativePath: String) -> ScannedFile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
        return ScannedFile(
            relativePath: relativePath,
            title: MarkdownSummary.title(in: String(decoding: data, as: UTF8.self)),
            kind: .detect(relativePath: relativePath),
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            modifiedAt: modified
        )
    }

    /// Calls visit for each Markdown file and returns the ignored folders and Markdown files. Symbolic links are skipped.
    private static func walk(root: URL, rules: IgnoreRules, visit: (URL, String) -> ()) -> [String] {
        let root = Paths.canonical(root)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else {
            return []
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
