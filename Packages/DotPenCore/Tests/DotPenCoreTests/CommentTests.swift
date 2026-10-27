import Foundation
import Testing
@testable import DotPenCore

private let plan = """
# Rate limiter rollout

Move the API from a fixed per-IP limit to a token bucket per API key.

## Steps

- [x] Add `TokenBucket` with Redis backing
- [ ] Shadow mode: log every decision, block nothing
- [ ] Roll out to internal keys for one day
"""

@Test func aPassageIsFoundInItsBlock() {
    #expect(CommentAnchor.locate(quote: "internal keys for one day", near: 9, in: plan) == LineRange(start: 9, end: 9))
}

@Test func aPassageFollowsItsBlockWhenLinesMove() {
    let edited = plan.replacingOccurrences(of: "## Steps\n", with: "## Steps\n\nFirst, a word on scope.\n")
    #expect(CommentAnchor.locate(quote: "internal keys for one day", near: 9, in: edited) == LineRange(start: 11, end: 11))
}

@Test func aPassageThatWasRewrittenIsLost() {
    let edited = plan.replacingOccurrences(of: "internal keys for one day", with: "everyone")
    #expect(CommentAnchor.locate(quote: "internal keys for one day", near: 9, in: edited) == nil)
}

@Test func theNearestCopyWins() {
    let doubled = plan + "\n\nRoll out to internal keys for one day, again.\n"
    #expect(CommentAnchor.locate(quote: "internal keys for one day", near: 11, in: doubled) == LineRange(start: 11, end: 11))
    #expect(CommentAnchor.locate(quote: "internal keys for one day", near: 9, in: doubled) == LineRange(start: 9, end: 9))
}

@Test func thePromptMatchesThePrototype() {
    let prompt = PromptBuilder.prompt(path: "docs/plans/rate-limiter.md", noun: "plan", items: [
        .init(lineStart: 14, lineEnd: 14, quote: "Roll out to internal keys for one day", body: "One day on internal keys is enough. Then 5%, and watch p99 latency."),
    ])
    #expect(prompt == """
    Review notes on docs/plans/rate-limiter.md

    1. On line 14, "Roll out to internal keys for one day"
       One day on internal keys is enough. Then 5%,
       and watch p99 latency.

    Update the plan with these changes, then stop.
    """)
}

@Test func longPassagesAreShortenedAndRangesNamed() {
    let quote = String(repeating: "word ", count: 30)
    let prompt = PromptBuilder.prompt(path: "a.md", noun: "file", items: [.init(lineStart: 3, lineEnd: 5, quote: quote, body: "Fix.")])
    #expect(prompt.contains("1. On lines 3–5, \""))
    #expect(prompt.contains("…\""))
}

@Test func changeNotesListEachChangeInOrder() {
    var changes = ChangeSet()
    changes.added = [LineRange(start: 8, end: 8)]
    changes.removed = [Removal(afterLine: 7, lineCount: 1, text: "x")]
    #expect(PromptBuilder.changeNotes(changes, in: plan) == [
        "1 line removed after line 7",
        "Added on line 8: \"Shadow mode: log every decision, block nothing\"",
    ])
}

@MainActor @Test func commentsAreSavedFollowedAndSent() async throws {
    let temp = try TempFolder()
    try temp.write("plan.md", plan)
    let library = Library(database: try .inMemory())
    try await library.addFolder(temp.url)
    let document = try #require(library.folders.first?.documents.first)
    let saved = try #require(library.addComment(to: document, quote: "internal keys for one day", line: 9, body: "One day is enough.", text: plan))
    #expect(saved.lineStart == 9 && saved.isInPrompt)
    #expect(library.commentsVersion == 1)
    let edited = plan.replacingOccurrences(of: "## Steps\n", with: "## Steps\n\nScope first.\n")
    let anchored = library.comments(for: document, text: edited)
    #expect(anchored.first?.range == LineRange(start: 11, end: 11))
    #expect(anchored.first?.comment.lineStart == 11)
    #expect(library.openComments().count == 1)
    library.markSent([anchored[0].comment], resolve: true)
    #expect(library.openComments().isEmpty)
    let after = library.comments(for: document, text: edited).first?.comment
    #expect(after?.status == .resolved && after?.sentAt != nil)
}

@Test func aSelectionCopiesAsAReference() {
    #expect(PromptBuilder.reference(path: "docs/plans/rate-limiter.md", lineStart: 15, lineEnd: 15, quote: "Roll out to internal keys for one day")
        == #"In docs/plans/rate-limiter.md, line 15: "Roll out to internal keys for one day""#)
    #expect(PromptBuilder.reference(path: "README.md", lineStart: 3, lineEnd: 5, quote: "Run make dev")
        == #"In README.md, lines 3–5: "Run make dev""#)
    #expect(DocumentKind.plan.promptNoun == "plan")
}
