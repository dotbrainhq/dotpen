import Foundation

/// Ticking a task box, the one edit DotMD makes to a file. Only the box's character changes, so line numbers,
/// line endings and everything else in the file stay as they were.
public enum TaskToggle {
    public struct Tick: Equatable, Sendable {
        public let text: String
        public let oldLine: String
        public let newLine: String
    }

    /// The text with the task on the 1-based line set to checked. Nil when that line isn't a task outside fenced code,
    /// or is already in that state: the file changed since the page was drawn.
    public static func toggle(_ text: String, line: Int, checked: Bool) -> Tick? {
        // Foundation splits by code unit, so a CRLF line keeps its \r; Swift would treat "\r\n" as one character.
        var lines = text.components(separatedBy: "\n")
        guard line >= 1, line <= lines.count, !isInFence(line, lines) else { return nil }
        let old = lines[line - 1]
        guard let match = old.firstMatch(of: /^((?:[ \t]*>)*[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+\[)([ xX])(\][ \t])/) else {
            return nil
        }
        guard (match.output.2 != " ") != checked else { return nil }
        let new = match.output.1 + (checked ? "x" : " ") + old[match.output.3.startIndex...]
        lines[line - 1] = String(new)
        return Tick(text: lines.joined(separator: "\n"), oldLine: trimmingReturn(old), newLine: trimmingReturn(String(new)))
    }

    /// The copy of the file last read, with the same tick, so the tick doesn't show as a change. Nil unless the
    /// ticked line appears in it exactly once.
    public static func mirror(_ text: String, from oldLine: String, to newLine: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        let matches = lines.indices.filter { trimmingReturn(lines[$0]) == oldLine }
        guard matches.count == 1, let index = matches.first else { return nil }
        lines[index] = newLine + (lines[index].hasSuffix("\r") ? "\r" : "")
        return lines.joined(separator: "\n")
    }

    private static func isInFence(_ line: Int, _ lines: [String]) -> Bool {
        var fence: String?
        for text in lines.prefix(line - 1) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(marker) { fence = nil }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
            }
        }
        return fence != nil
    }

    private static func trimmingReturn(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }
}
