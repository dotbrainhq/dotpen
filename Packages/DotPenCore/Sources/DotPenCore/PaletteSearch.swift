import Foundation
import Markdown

/// A heading in a file and its source line, for the palette's jump to a heading.
public struct DocumentHeading: Equatable, Sendable {
    public var level: Int
    public var title: String
    public var line: Int

    public init(level: Int, title: String, line: Int) {
        self.level = level
        self.title = title
        self.line = line
    }
}

public enum DocumentHeadings {
    /// The top-level headings in reading order, with the lines the renderer tags them with.
    public static func headings(in text: String) -> [DocumentHeading] {
        let parsed = MarkdownBlocks.outline(text)
        return zip(parsed.blocks, parsed.markups).compactMap { block, markup in
            guard let heading = markup as? Heading else { return nil }
            let title = MarkdownBlocks.words(of: heading).joined(separator: " ")
            return title.isEmpty ? nil : DocumentHeading(level: heading.level, title: title, line: block.startLine)
        }
    }
}

/// The palette's matching: every letter of the query, in order, anywhere in the text. Matches that start words,
/// run together, or start the text score higher, so "tbd" finds "Token bucket design" before "attributed".
public enum FuzzyMatch {
    public static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let original = Array(text)
        let haystack = Array(text.lowercased())
        guard haystack.count == original.count else { return nil }
        var score = 0
        var index = 0
        var previous: Int?
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return nil }
            score += 1
            if found == 0 || !original[found - 1].isLetter && !original[found - 1].isNumber
                || original[found].isUppercase && original[found - 1].isLowercase {
                score += 6
            }
            if let previous {
                if found == previous + 1 { score += 4 } else { score -= min(found - previous - 1, 3) }
            }
            previous = found
            index = found + 1
        }
        let lowered = String(haystack)
        let joined = String(needle)
        if lowered.hasPrefix(joined) { score += 12 } else if lowered.contains(joined) { score += 6 }
        return score
    }
}
