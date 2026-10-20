import Foundation

extension DocumentKind {
    static let agentFileNames: Set<String> = ["claude.md", "agents.md", "gemini.md", "copilot-instructions.md", "claude.local.md"]

    /// Guesses what a document is from its path, the way people name these files.
    public static func detect(relativePath: String) -> DocumentKind {
        let parts = relativePath.lowercased().split(separator: "/").map(String.init)
        guard let name = parts.last else { return .other }
        let directories = parts.dropLast()
        let stem = (name as NSString).deletingPathExtension
        let planWords: Set<String> = ["plan", "plans", "planning"]
        // Whole words only, so "explanation" doesn't count as a plan.
        let words = stem.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)

        if agentFileNames.contains(name) || directories.contains(".claude") || directories.contains(".cursor") {
            return .agentInstructions
        }
        if stem.hasPrefix("readme") { return .readme }
        if stem.hasPrefix("changelog") || ["changes", "history", "news", "releases", "release-notes"].contains(stem) {
            return .changelog
        }
        if words.contains(where: { planWords.contains($0) }) || directories.contains(where: { planWords.contains($0) }) {
            return .plan
        }
        let specStemWords: Set<String> = ["spec", "specs", "specification", "specifications", "design", "rfc", "adr"]
        let specFolders: Set<String> = ["spec", "specs", "specification", "specifications", "rfc", "rfcs", "adr", "adrs", "design", "designs"]
        let isSpec = words.contains(where: { specStemWords.contains($0) }) || directories.contains(where: { specFolders.contains($0) })
        return isSpec ? .spec : .other
    }
}
