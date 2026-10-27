import Foundation

/// A folder first launch offers to watch.
public struct AgentFolderCandidate: Identifiable, Equatable, Sendable {
    public var url: URL
    /// Agent files found at the folder's top level, like CLAUDE.md or .cursor.
    public var markers: [String]
    public var markdownCount: Int

    public var id: String { url.path }
    /// Folders with agent files start switched on.
    public var isSuggested: Bool { !markers.isEmpty }
}

/// Finds the projects inside a code folder that agents work in.
public enum AgentFolderFinder {
    public static let markers = ["CLAUDE.md", "AGENTS.md", "GEMINI.md", ".claude", ".cursor"]
    /// A folder without agent files is offered, switched off, when it holds at least this many Markdown files.
    public static let minimumMarkdownWithoutMarkers = 10

    /// The chosen folder itself when it has agent files, then its subfolders: agent folders first, by name.
    public static func candidates(in codeFolder: URL) -> [AgentFolderCandidate] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let children = (try? fileManager.contentsOfDirectory(at: codeFolder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let subfolders = children.filter { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.isDirectory == true && values?.isPackage != true && !IgnoreRules.builtInDirectories.contains(url.lastPathComponent)
        }

        var candidates: [AgentFolderCandidate] = []
        for folder in [codeFolder] + subfolders {
            let found = markers.filter { fileManager.fileExists(atPath: folder.appending(path: $0).path) }
            // Counting the whole code folder would walk every project in it, so it only counts when it is a project itself.
            if folder == codeFolder && found.isEmpty { continue }
            let count = FolderScanner.countMarkdown(root: folder, rules: .load(root: folder))
            guard !found.isEmpty || count >= minimumMarkdownWithoutMarkers else { continue }
            candidates.append(AgentFolderCandidate(url: folder, markers: found, markdownCount: count))
        }
        return candidates.sorted { a, b in
            if a.isSuggested != b.isSuggested { return a.isSuggested }
            return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
    }
}
