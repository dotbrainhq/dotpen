import Testing
@testable import DotPenCore

@Test func titleComesFromTheFirstHeading() {
    #expect(MarkdownSummary.title(in: "Intro line\n\n## Rate limiter rollout\n\n# Later") == "Rate limiter rollout")
}

@Test func frontMatterTitleWins() {
    #expect(MarkdownSummary.title(in: "---\nstatus: draft\ntitle: \"Billing webhooks\"\n---\n\n# Something else") == "Billing webhooks")
}

@Test func frontMatterIsSkippedWhenItHasNoTitle() {
    #expect(MarkdownSummary.title(in: "---\nstatus: draft\n---\n# Plan") == "Plan")
}

@Test func headingsInCodeFencesAreIgnored() {
    #expect(MarkdownSummary.title(in: "```sh\n# not a heading\n```\n\n# Real title") == "Real title")
}

@Test func setextHeadingsCount() {
    #expect(MarkdownSummary.title(in: "Token bucket design\r\n===\r\n\r\nBody") == "Token bucket design")
}

@Test func indentedCodeIsNotAHeading() {
    #expect(MarkdownSummary.title(in: "    # comment in code\n\n# Real") == "Real")
}

@Test func h2SetextHeadingsCount() {
    #expect(MarkdownSummary.title(in: "Title two\n---\n\nbody") == "Title two")
}

@Test func aLoneRuleIsNotATitle() {
    #expect(MarkdownSummary.title(in: "Intro\n\n---\n\n# Real") == "Real")
}

@Test func byteOrderMarkIsIgnored() {
    #expect(MarkdownSummary.title(in: "\u{FEFF}# Title\n\n## Two") == "Title")
}

@Test func closingHashesAndInlineMarksAreRemoved() {
    #expect(MarkdownSummary.title(in: "# The `TokenBucket` **plan** ##") == "The TokenBucket plan")
    #expect(MarkdownSummary.title(in: "# See [the spec](spec.md)") == "See the spec")
    #expect(MarkdownSummary.title(in: "# C#") == "C#")
}

@Test func noHeadingMeansNoTitle() {
    #expect(MarkdownSummary.title(in: "Just a paragraph.\n\n#hashtag is not a heading") == nil)
}

@Test(arguments: [
    ("README.md", DocumentKind.readme),
    ("docs/readme-dev.md", .readme),
    ("CLAUDE.md", .agentInstructions),
    ("AGENTS.md", .agentInstructions),
    (".claude/commands/review.md", .agentInstructions),
    (".github/copilot-instructions.md", .agentInstructions),
    ("CHANGELOG.md", .changelog),
    ("HISTORY.md", .changelog),
    ("docs/plans/rate-limiter.md", .plan),
    ("rollout-plan.md", .plan),
    ("docs/specs/token-bucket.md", .spec),
    ("billing-design.md", .spec),
    ("docs/adr/0001-use-sqlite.md", .spec),
    ("explanation.md", .other),
    ("notes/HANDOFF.md", .other),
    ("planet.md", .other),
    ("docs/special-offers.md", .other),
    ("specific.md", .other),
    ("planning/q3.md", .plan),
    ("docs/specs/api.md", .spec),
    ("NEWS.md", .changelog),
    ("CLAUDE.local.md", .agentInstructions),
])
func kindComesFromThePath(path: String, kind: DocumentKind) {
    #expect(DocumentKind.detect(relativePath: path) == kind)
}
