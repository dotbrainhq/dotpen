import Foundation
import Testing
@testable import DotMDCore

private let before = """
# Rate limiter rollout

Move the API from a fixed per-IP limit to a token bucket per API key. Ship it behind a flag and roll it out to 10% of traffic.

## Steps

- [x] Add `TokenBucket` with Redis backing
- [x] Load the limits from config
- [x] Put it behind the `rate_limit_v2` flag
- [ ] Roll out to internal keys for one day
"""

/// The prototype's three changes: words rewritten in the paragraph, a step removed, a step added.
private let after = """
# Rate limiter rollout

Move the API from a fixed per-IP limit to a token bucket per API key. Ship it behind a flag and roll it out to internal keys first, then 5% of traffic.

## Steps

- [x] Add `TokenBucket` with Redis backing
- [x] Put it behind the `rate_limit_v2` flag
- [ ] Shadow mode: log every decision, block nothing
- [ ] Roll out to internal keys for one day
"""

@Test func identicalTextHasNoChanges() {
    #expect(ChangeDiff.changes(from: before, to: before).isEmpty)
}

@Test func thePrototypeScenarioHasThreeChanges() {
    let changes = ChangeDiff.changes(from: before, to: after)
    #expect(changes.count == 3)
    #expect(changes.changed.map(\.start) == [3])
    #expect(changes.added == [LineRange(start: 9, end: 9)])
    #expect(changes.removed == [Removal(afterLine: 7, lineCount: 1, text: "- [x] Load the limits from config")])
    #expect(changes.lines == [3, 7, 9])
}

@Test func rewrittenWordsAreDeletedThenInserted() {
    let changes = ChangeDiff.changes(from: before, to: after)
    #expect(changes.changed[0].words == [
        WordOp(kind: .keep, count: 25, text: nil),
        WordOp(kind: .delete, count: 0, text: "10%"),
        WordOp(kind: .insert, count: 5, text: nil),
        WordOp(kind: .keep, count: 2, text: nil),
    ])
}

@Test func aBlockAtTheTopRemovedHasNoBlockBefore() {
    let changes = ChangeDiff.changes(from: "Intro line.\n\n# Title\n", to: "# Title\n")
    #expect(changes.removed == [Removal(afterLine: 0, lineCount: 1, text: "Intro line.")])
}

@Test func consecutiveRemovedBlocksAreOneRemoval() {
    let changes = ChangeDiff.changes(from: "# T\n\nOne.\n\nTwo\nlines.\n\nEnd.\n", to: "# T\n\nEnd.\n")
    #expect(changes.removed == [Removal(afterLine: 1, lineCount: 3, text: "One.\n\nTwo\nlines.")])
}

@Test func unrelatedReplacementIsRemovedAndAdded() {
    let changes = ChangeDiff.changes(from: "# T\n\nApples and pears.\n", to: "# T\n\nCompletely different words here.\n")
    #expect(changes.changed.isEmpty)
    #expect(changes.added == [LineRange(start: 3, end: 3)])
    #expect(changes.removed.count == 1)
}

@Test func frontMatterEditsAreNotBlockChanges() {
    #expect(ChangeDiff.changes(from: "---\nstatus: draft\n---\n# T\n", to: "---\nstatus: done\n---\n# T\n").isEmpty)
}

@Test func lineEndingsAloneAreNotChanges() {
    #expect(ChangeDiff.changes(from: "# T\n\nText.\n", to: "# T\r\n\r\nText.\r\n").isEmpty)
}

@Test func changeSetsEncodeForTheRenderer() throws {
    let changes = ChangeDiff.changes(from: before, to: after)
    let json = String(decoding: try JSONEncoder().encode(changes), as: UTF8.self)
    #expect(json.contains(#""kind":"delete""#))
    #expect(json.contains(#""afterLine":7"#))
}

/// The spec's budget: apply a live change in under 100 ms. Runs only with DOTMD_PERF=1, in release.
@Test(.enabled(if: ProcessInfo.processInfo.environment["DOTMD_PERF"] == "1"))
func diffsAMegabyteFileInUnderAHundredMilliseconds() {
    let paragraph = "The bucket refills at a steady rate and every request takes one token from it. "
    var blocks = (0..<4_000).map { "Paragraph \($0). " + String(repeating: paragraph, count: 3) }
    let old = blocks.joined(separator: "\n\n")
    blocks[2_000] = blocks[2_000].replacingOccurrences(of: "steady", with: "constant")
    let new = blocks.joined(separator: "\n\n")
    #expect(old.utf8.count > 1_000_000)
    var changes = ChangeSet()
    let elapsed = ContinuousClock().measure { changes = ChangeDiff.changes(from: old, to: new) }
    #expect(changes.changed.count == 1)
    #expect(elapsed < .milliseconds(100), "Diff took \(elapsed)")
}

private let readText = "# Plan\n\nShip it behind a flag.\n\nRoll out to internal keys.\n\nLog every decision.\n"
private let agentText = "# Plan\n\nShip it behind a flag for a week.\n\nAlert on every 429.\n\nRoll out to internal keys.\n"

@Test func acceptingAChangedBlockLeavesTheOthersMarked() throws {
    let before = ChangeDiff.changes(from: readText, to: agentText)
    #expect(before.changed.map(\.start) == [3])
    #expect(before.added.map(\.start) == [5])
    #expect(before.removed.count == 1)
    let read = try #require(ChangeDiff.accepting(.changed, at: 3, from: readText, to: agentText))
    let after = ChangeDiff.changes(from: read, to: agentText)
    #expect(after.changed.isEmpty)
    #expect(after.added == before.added)
    #expect(after.removed.map(\.text) == before.removed.map(\.text))
}

@Test func acceptingAnAddedBlockOrARemovalTakesOnlyThatOne() throws {
    let added = try #require(ChangeDiff.accepting(.added, at: 5, from: readText, to: agentText))
    let afterAdded = ChangeDiff.changes(from: added, to: agentText)
    #expect(afterAdded.added.isEmpty)
    #expect(afterAdded.changed.map(\.start) == [3])
    #expect(afterAdded.removed.count == 1)
    let line = try #require(ChangeDiff.changes(from: readText, to: agentText).removed.first).afterLine
    let removed = try #require(ChangeDiff.accepting(.removed, at: line, from: readText, to: agentText))
    let afterRemoved = ChangeDiff.changes(from: removed, to: agentText)
    #expect(afterRemoved.removed.isEmpty)
    #expect(afterRemoved.count == 2)
}

@Test func acceptingEveryChangeOneByOneLeavesNothing() throws {
    var read = readText
    while let line = ChangeDiff.changes(from: read, to: agentText).lines.first {
        let set = ChangeDiff.changes(from: read, to: agentText)
        let kind: ChangeKind = set.changed.contains { $0.start == line } ? .changed : set.added.contains { $0.start == line } ? .added : .removed
        let at = kind == .removed ? try #require(set.removed.first { max($0.afterLine, 1) == line }).afterLine : line
        read = try #require(ChangeDiff.accepting(kind, at: at, from: read, to: agentText))
    }
    #expect(ChangeDiff.changes(from: read, to: agentText).isEmpty)
}

@Test func acceptingALineWithNoChangeReturnsNothing() {
    #expect(ChangeDiff.accepting(.changed, at: 1, from: readText, to: agentText) == nil)
}
