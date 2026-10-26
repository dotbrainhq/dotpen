import Foundation
import Testing
@testable import DotPenCore

@Test func agentFoldersAreSuggestedAndBigMarkdownFoldersOffered() throws {
    let code = try TempFolder()
    try code.write("api-gateway/CLAUDE.md", "# Rules")
    try code.write("api-gateway/docs/plan.md", "# Plan")
    try code.write("api-gateway/docs/spec.md", "# Spec")
    try code.write("web-app/AGENTS.md", "# Rules")
    try code.write("web-app/.cursor/rules.mdc", "rules")
    for index in 0..<12 {
        try code.write("old-site/posts/post-\(index).md", "# Post \(index)")
    }
    try code.write("scripts/README.md", "# Scripts")
    let candidates = AgentFolderFinder.candidates(in: code.url)
    #expect(candidates.map(\.url.lastPathComponent) == ["api-gateway", "web-app", "old-site"])
    #expect(candidates[0].markers == ["CLAUDE.md"])
    #expect(candidates[0].markdownCount == 3)
    #expect(candidates[1].markers == ["AGENTS.md", ".cursor"])
    #expect(candidates[1].isSuggested)
    #expect(!candidates[2].isSuggested)
    #expect(candidates[2].markdownCount == 12)
}

@Test func aRepoChosenDirectlyIsItsOwnCandidate() throws {
    let repo = try TempFolder()
    try repo.write("CLAUDE.md", "# Rules")
    try repo.write("docs/plan.md", "# Plan")
    let candidates = AgentFolderFinder.candidates(in: repo.url)
    #expect(candidates.first?.url.path == repo.url.path)
    #expect(candidates.first?.markers == ["CLAUDE.md"])
}
