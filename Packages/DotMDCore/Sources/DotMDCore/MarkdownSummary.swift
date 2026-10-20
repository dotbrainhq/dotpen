import Foundation

/// Reads a document's title without a full Markdown parse.
public enum MarkdownSummary {
    /// The front matter `title:` field, else the first heading outside code fences.
    public static func title(in text: String) -> String? {
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        // Swift treats "\r\n" as one Character, so split on any newline character rather than "\n" alone.
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)
        var index = 0
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.indices.dropFirst().first(where: { ["---", "..."].contains(lines[$0].trimmingCharacters(in: .whitespaces)) }) {
            for line in lines[1..<end] where line.hasPrefix("title:") {
                let value = unquote(String(line.dropFirst("title:".count)))
                if !value.isEmpty { return value }
            }
            index = end + 1
        }
        var fence: String?
        var previous = ""
        while index < lines.count {
            let line = lines[index]
            index += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(marker) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                previous = ""
                continue
            }
            let isIndentedCode = line.hasPrefix("    ") || line.hasPrefix("\t")
            if !isIndentedCode, let heading = atxHeading(trimmed) { return heading }
            if !previous.isEmpty, !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "=" }) || trimmed.allSatisfy({ $0 == "-" }) {
                return clean(previous)
            }
            previous = isIndentedCode ? "" : trimmed
        }
        return nil
    }

    static func atxHeading(_ line: String) -> String? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        if text.allSatisfy({ $0 == "#" }) {
            text = ""
        } else if let closing = text.range(of: #"\s+#+$"#, options: .regularExpression) {
            text.removeSubrange(closing)
        }
        let title = clean(text)
        return title.isEmpty ? nil : title
    }

    /// Strips inline Markdown that reads badly in a list: links keep their text, bold and code marks go.
    static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for mark in ["**", "__", "`"] {
            result = result.replacingOccurrences(of: mark, with: "")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, first == trimmed.last, first == "\"" || first == "'" else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }
}
