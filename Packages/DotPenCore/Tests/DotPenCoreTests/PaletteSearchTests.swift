import Testing
@testable import DotPenCore

@Test func fuzzyMatchesNeedEveryLetterInOrder() {
    #expect(FuzzyMatch.score("rlr", in: "Rate limiter rollout") != nil)
    #expect(FuzzyMatch.score("rate", in: "Rate limiter rollout") != nil)
    #expect(FuzzyMatch.score("xyz", in: "Rate limiter rollout") == nil)
    #expect(FuzzyMatch.score("tuor", in: "Rate limiter rollout") == nil)
    #expect(FuzzyMatch.score("", in: "Anything") == 0)
}

@Test func betterMatchesScoreHigher() throws {
    let prefix = try #require(FuzzyMatch.score("token", in: "Token bucket design"))
    let inside = try #require(FuzzyMatch.score("token", in: "Rate limiter with token buckets"))
    let scattered = try #require(FuzzyMatch.score("token", in: "Take one kitten"))
    #expect(prefix > inside)
    #expect(inside > scattered)
    let wordStarts = try #require(FuzzyMatch.score("tbd", in: "Token bucket design"))
    let middles = try #require(FuzzyMatch.score("tbd", in: "attributed"))
    #expect(wordStarts > middles)
}

@Test func headingsCarryTheirLevelAndLine() {
    let text = "---\nstatus: draft\n---\n# Rate limiter rollout\n\nIntro.\n\n## Steps\n\n- [ ] One\n\n### Detail\n\n## Open question\n"
    #expect(DocumentHeadings.headings(in: text) == [
        DocumentHeading(level: 1, title: "Rate limiter rollout", line: 4),
        DocumentHeading(level: 2, title: "Steps", line: 8),
        DocumentHeading(level: 3, title: "Detail", line: 12),
        DocumentHeading(level: 2, title: "Open question", line: 14),
    ])
}

@Test func openTasksAreTheUntickedOnesOutsideCode() {
    let text = """
    # Plan

    - [x] Add TokenBucket
    - [ ] Shadow mode: log every decision
      * [ ] Nested step
    1. [ ] Numbered step
    - [X] Done too

    ```md
    - [ ] Not a task, it's an example
    ```
    """
    #expect(OpenTasks.find(in: text) == ["Shadow mode: log every decision", "Nested step", "Numbered step"])
}

@Test func openTasksAreFoundInFilesWithWindowsLineEndings() {
    let text = "# Plan\r\n\r\n- [ ] Load limits\r\n- [x] Log decisions\r\n```\r\n- [ ] example\r\n```\r\n- [ ] Ship it\r\n"
    #expect(OpenTasks.find(in: text) == ["Load limits", "Ship it"])
}
