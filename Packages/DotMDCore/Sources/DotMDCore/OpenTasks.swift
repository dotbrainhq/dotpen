import Foundation

/// Unticked task list items, for Shortcuts' List Open Tasks. Examples inside fenced code don't count.
public enum OpenTasks {
    public static func find(in text: String) -> [String] {
        var tasks: [String] = []
        var fence: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(marker) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                continue
            }
            if let match = trimmed.wholeMatch(of: /(?:[-*+]|\d+[.)])\s+\[ \]\s+(.+)/) {
                tasks.append(String(match.output.1).trimmingCharacters(in: .whitespaces))
            }
        }
        return tasks
    }
}
