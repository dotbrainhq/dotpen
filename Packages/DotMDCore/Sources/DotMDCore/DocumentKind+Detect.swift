import Foundation

extension DocumentKind {
    static let agentFileNames: Set<String> = ["claude.md", "agents.md", "gemini.md", "copilot-instructions.md"]

    /// Guesses what a document is from its path, the way people name these files.
    public static func detect(relativePath: String) -> DocumentKind {
        let parts = relativePath.lowercased().split(separator: "/").map(String.init)
        guard let name = parts.last else { return .other }
        let directories = parts.dropLast()
        let stem = (name as NSString).deletingPathExtension
        // Whole words only, so "explanation" doesn't count as a plan.
        let words = stem.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)

        if agentFileNames.contains(name) || directories.contains(".claude") || directories.contains(".cursor") {
            return .agentInstructions
        }
        if stem.hasPrefix("readme") { return .readme }
        if stem.hasPrefix("changelog") || ["changes", "history", "releases", "release-notes"].contains(stem) {
            return .changelog
        }
        if words.contains(where: { $0.hasPrefix("plan") }) || directories.contains(where: { $0.hasPrefix("plan") }) {
            return .plan
        }
        let specWords = words.contains { $0.hasPrefix("spec") || $0 == "design" || $0 == "rfc" || $0 == "adr" }
        let specFolder = directories.contains { $0.hasPrefix("spec") || $0.hasPrefix("rfc") || $0 == "adr" || $0 == "design" }
        return specWords || specFolder ? .spec : .other
    }
}
