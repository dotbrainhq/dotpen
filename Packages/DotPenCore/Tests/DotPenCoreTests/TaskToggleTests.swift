import Testing
@testable import DotPenCore

@Test func tickingFlipsOnlyTheBoxOnThatLine() throws {
    let text = "# Plan\n\n- [ ] Load limits\n- [x] Log decisions\n"
    let tick = try #require(TaskToggle.toggle(text, line: 3, checked: true))
    #expect(tick.text == "# Plan\n\n- [x] Load limits\n- [x] Log decisions\n")
    #expect(tick.oldLine == "- [ ] Load limits")
    #expect(tick.newLine == "- [x] Load limits")
    let untick = try #require(TaskToggle.toggle(text, line: 4, checked: false))
    #expect(untick.text == "# Plan\n\n- [ ] Load limits\n- [ ] Log decisions\n")
}

@Test func tickingKeepsMarkersIndentsQuotesAndLineEndings() throws {
    #expect(TaskToggle.toggle("  * [ ] nested", line: 1, checked: true)?.text == "  * [x] nested")
    #expect(TaskToggle.toggle("1. [X] numbered", line: 1, checked: false)?.text == "1. [ ] numbered")
    #expect(TaskToggle.toggle("> - [ ] quoted", line: 1, checked: true)?.text == "> - [x] quoted")
    #expect(TaskToggle.toggle("- [ ] one\r\n- [ ] two\r\n", line: 2, checked: true)?.text == "- [ ] one\r\n- [x] two\r\n")
}

@Test func tickingRefusesAnythingButATaskInTheExpectedState() {
    #expect(TaskToggle.toggle("- [x] done", line: 1, checked: true) == nil)
    #expect(TaskToggle.toggle("- plain item", line: 1, checked: true) == nil)
    #expect(TaskToggle.toggle("- [ ]no space", line: 1, checked: true) == nil)
    #expect(TaskToggle.toggle("- [ ] one", line: 2, checked: true) == nil)
    #expect(TaskToggle.toggle("- [ ] one", line: 0, checked: true) == nil)
    #expect(TaskToggle.toggle("```\n- [ ] example\n```", line: 2, checked: true) == nil)
}

@Test func theReadCopyTakesTheSameTickWhenTheLineIsThereOnce() {
    let read = "# Plan\n\n- [ ] Load limits\n"
    #expect(TaskToggle.mirror(read, from: "- [ ] Load limits", to: "- [x] Load limits") == "# Plan\n\n- [x] Load limits\n")
    #expect(TaskToggle.mirror("- [ ] a\n- [ ] a\n", from: "- [ ] a", to: "- [x] a") == nil)
    #expect(TaskToggle.mirror("- [ ] b\n", from: "- [ ] a", to: "- [x] a") == nil)
}
