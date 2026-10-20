import Darwin
import Foundation

/// Decides which paths the file list hides: build output and dependencies by name, plus the folder's root .gitignore.
/// Covers the common .gitignore forms (names, globs, a leading slash, a trailing slash, and "**" as a whole path
/// segment that matches any number of folders). Negation lines are skipped.
public struct IgnoreRules: Sendable {
    public static let builtInDirectories: Set<String> = [
        ".git", "node_modules", "build", "dist", "DerivedData", ".build", "Pods", ".next", ".nuxt",
        ".svelte-kit", ".turbo", ".venv", "venv", "__pycache__", "coverage", ".cache",
    ]

    /// Hides nothing. Used when the person chooses to show ignored paths.
    public static let none = IgnoreRules(patterns: [], usesBuiltIn: false)

    private let patterns: [Pattern]
    private let usesBuiltIn: Bool

    public init(gitignore: String? = nil) {
        let lines = (gitignore ?? "").split(whereSeparator: \.isNewline).map(String.init)
        self.init(patterns: lines.compactMap(Pattern.init), usesBuiltIn: true)
    }

    private init(patterns: [Pattern], usesBuiltIn: Bool) {
        self.patterns = patterns
        self.usesBuiltIn = usesBuiltIn
    }

    public static func load(root: URL) -> IgnoreRules {
        IgnoreRules(gitignore: try? String(contentsOf: root.appending(path: ".gitignore"), encoding: .utf8))
    }

    public func isIgnored(_ relativePath: String, isDirectory: Bool) -> Bool {
        let name = (relativePath as NSString).lastPathComponent
        if usesBuiltIn, isDirectory, Self.builtInDirectories.contains(name) { return true }
        return patterns.contains { $0.matches(relativePath, name: name, isDirectory: isDirectory) }
    }

    /// True when the path or any folder above it is ignored. File events name single paths, so the whole chain is checked.
    public func containsIgnoredPath(_ relativePath: String) -> Bool {
        let parts = relativePath.split(separator: "/")
        for end in parts.indices {
            let prefix = parts[...end].joined(separator: "/")
            if end < parts.count - 1 {
                if isIgnored(prefix, isDirectory: true) { return true }
            } else if isIgnored(prefix, isDirectory: false) || isIgnored(prefix, isDirectory: true) {
                // The last part may name a file or a folder, and an event doesn't say which.
                return true
            }
        }
        return false
    }

    struct Pattern: Sendable {
        let segments: [String]
        let anchored: Bool
        let directoryOnly: Bool

        init?(_ line: String) {
            var text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.hasPrefix("#"), !text.hasPrefix("!") else { return nil }
            var directoryOnly = false
            var anchored = false
            if text.hasSuffix("/**") {
                text.removeLast(3)
                directoryOnly = true
                anchored = true
            }
            if text.hasSuffix("/") {
                text.removeLast()
                directoryOnly = true
            }
            var floating = false
            if text.hasPrefix("**/") {
                text.removeFirst(3)
                floating = true
            }
            if text.hasPrefix("/") {
                text.removeFirst()
                anchored = true
            } else if text.contains("/") && !floating {
                anchored = true
            }
            guard !text.isEmpty else { return nil }
            segments = text.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            self.anchored = anchored
            self.directoryOnly = directoryOnly
            if segments.isEmpty { return nil }
        }

        func matches(_ path: String, name: String, isDirectory: Bool) -> Bool {
            if directoryOnly && !isDirectory { return false }
            if segments.count == 1 && !anchored { return fnmatch(segments[0], name, 0) == 0 }
            let components = path.split(separator: "/").map(String.init)
            if anchored { return Self.match(segments[...], components[...]) }
            return components.indices.contains { Self.match(segments[...], components[$0...]) }
        }

        /// "**" takes zero or more path components. Any other segment takes exactly one. The whole path must be used.
        private static func match(_ glob: ArraySlice<String>, _ path: ArraySlice<String>) -> Bool {
            guard let first = glob.first else { return path.isEmpty }
            if first == "**" {
                let rest = glob.dropFirst()
                return (path.startIndex...path.endIndex).contains { match(rest, path[$0...]) }
            }
            guard let component = path.first, fnmatch(first, component, 0) == 0 else { return false }
            return match(glob.dropFirst(), path.dropFirst())
        }
    }
}
