import Foundation
import Testing
@testable import DotMDRender

@Test func readingOptionsDefaults() {
    let options = ReadingOptions()
    #expect(options.size == .medium)
    #expect(options.font == .serif)
    #expect(options.width == .medium)
    #expect(options.paper == .auto)
}

@Test func readingOptionsRoundTripThroughRawValue() {
    let options = ReadingOptions(size: .large, font: .mono, width: .wide, paper: .night)
    #expect(ReadingOptions(rawValue: options.rawValue) == options)
}

@Test func readingOptionsFillMissingFieldsWithDefaults() {
    let options = ReadingOptions(rawValue: #"{"size":"large"}"#)
    #expect(options == ReadingOptions(size: .large))
}

@Test func readingOptionsRejectBadRawValue() {
    #expect(ReadingOptions(rawValue: "not json") == nil)
}

@Test func renderCommandEscapesContent() throws {
    let command = ReaderCommand.render(markdown: "# \"Quoted\"\n</script>", options: ReadingOptions())
    let js = command.javaScript
    #expect(js.hasPrefix("window.DotMD.render("))
    #expect(js.hasSuffix(")"))
    #expect(!js.contains("</script>"))
    let json = String(js.dropFirst("window.DotMD.render(".count).dropLast())
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    #expect(object?["markdown"] as? String == "# \"Quoted\"\n</script>")
    let options = object?["options"] as? [String: String]
    #expect(options?["size"] == "medium")
}

@Test func setReadingOptionsCommand() {
    let js = ReaderCommand.setReadingOptions(ReadingOptions(size: .small, font: .sans, width: .narrow, paper: .paper)).javaScript
    #expect(js.contains("window.DotMD.setReadingOptions("))
    #expect(js.contains("\"paper\":\"paper\""))
    #expect(js.contains("\"size\":\"small\""))
}

@Test func messagesParse() {
    #expect(ReaderMessage(body: ["type": "ready"]) == .ready)
    #expect(ReaderMessage(body: ["type": "rendered"]) == .rendered)
    #expect(ReaderMessage(body: ["type": "linkActivated", "href": "https://example.com"]) == .linkActivated("https://example.com"))
    #expect(ReaderMessage(body: ["type": "copyText", "text": "let x"]) == .copyText("let x"))
    #expect(ReaderMessage(body: ["type": "diagramError", "line": 12, "message": "Parse error"]) == .diagramError(line: 12, message: "Parse error"))
    #expect(ReaderMessage(body: ["type": "unknown"]) == nil)
    #expect(ReaderMessage(body: "garbage") == nil)
}

@Test func bundledRendererIsPresent() {
    #expect(FileManager.default.fileExists(atPath: RendererResources.indexHTML.path))
    #expect(FileManager.default.fileExists(atPath: RendererResources.stylesheet.path))
    #expect(FileManager.default.fileExists(atPath: RendererResources.fontsDirectory.path))
}

@Test func layoutCommandPassesTheLayoutName() {
    #expect(ReaderCommand.setLayout(.document).javaScript == #"window.DotMD.setLayout("document")"#)
}

private struct SampleChanges: Encodable, Sendable {
    let added: [Int]
}

@Test func marksCommandCarriesTheChangesAndTheTime() {
    let command = ReaderCommand.applyMarks(changes: SampleChanges(added: [9]), since: "since 1:02 PM")
    #expect(command.javaScript == #"window.DotMD.applyMarks({"changes":{"added":[9]},"since":"since 1:02 PM"})"#)
}

@Test func changeCommandsPassTheirValues() {
    #expect(ReaderCommand.clearMarks(fade: true).javaScript == "window.DotMD.clearMarks(true)")
    #expect(ReaderCommand.setMemory(line: 42, label: "You stopped reading here at 1:02 PM").javaScript
        == #"window.DotMD.setMemory({"label":"You stopped reading here at 1:02 PM","line":42})"#)
    #expect(ReaderCommand.setMemory(line: nil, label: "").javaScript == #"window.DotMD.setMemory({"label":""})"#)
    #expect(ReaderCommand.markLive(lines: [5, 9]).javaScript == "window.DotMD.markLive([5,9])")
    #expect(ReaderCommand.setWriting(true, lastLine: 9).javaScript == #"window.DotMD.setWriting({"lastLine":9,"writing":true})"#)
}

@Test func changeMessagesAreRead() {
    #expect(ReaderMessage(body: ["type": "markRead"]) == .markRead)
    #expect(ReaderMessage(body: ["type": "scrollLine", "line": 12]) == .scrollLine(12))
    #expect(ReaderMessage(body: ["type": "scrollLine"]) == nil)
}

@Test func commentCommandsPassTheCommentsAndWhoWroteThem() {
    let comment = PageComment(id: 7, line: 15, quote: "Roll out to internal keys", body: "One day is enough.", when: "now", inPrompt: true, number: 1)
    #expect(ReaderCommand.setComments([comment], author: CommentAuthor(initial: "S", name: "You"), canComment: true).javaScript
        == #"window.DotMD.setComments({"author":{"initial":"S","name":"You"},"canComment":true,"items":[{"body":"One day is enough.","id":7,"inPrompt":true,"line":15,"number":1,"quote":"Roll out to internal keys","when":"now"}]})"#)
    #expect(ReaderCommand.setPanel(true).javaScript == "window.DotMD.setPanel(true)")
    #expect(ReaderCommand.reveal(line: 15).javaScript == "window.DotMD.reveal(15)")
    #expect(ReaderCommand.follow(line: 22).javaScript == "window.DotMD.follow(22)")
    #expect(ReaderCommand.nextChange.javaScript == "window.DotMD.nextChange()")
}

@Test func commentMessagesAreRead() {
    #expect(ReaderMessage(body: ["type": "saveComment", "line": 14, "quote": "log every decision", "body": "Log for a week.", "id": NSNull()])
        == .saveComment(line: 14, quote: "log every decision", body: "Log for a week.", id: nil))
    #expect(ReaderMessage(body: ["type": "saveComment", "line": 14, "quote": "q", "body": "b", "id": 7])
        == .saveComment(line: 14, quote: "q", body: "b", id: 7))
    #expect(ReaderMessage(body: ["type": "resolveComment", "id": 7]) == .resolveComment(id: 7))
    #expect(ReaderMessage(body: ["type": "copyPrompt", "line": 14, "quote": "q"]) == .copyPrompt(line: 14, quote: "q"))
    #expect(ReaderMessage(body: ["type": "saveComment", "line": 14]) == nil)
    #expect(ReaderMessage(body: ["type": "composing", "active": true]) == .composing(true))
    #expect(ReaderMessage(body: ["type": "composing"]) == nil)
    #expect(ReaderMessage(body: ["type": "toggleFollow"]) == .toggleFollow)
    #expect(ReaderMessage(body: ["type": "showShortcuts"]) == .showShortcuts)
    #expect(ReaderMessage(body: ["type": "noticeAction", "id": "find"]) == .noticeAction("find"))
}

@Test func noticeCommandsCarryTheNoticeOrNone() {
    let notice = PageNotice(icon: "trash", title: "plan.md was moved or deleted.", text: "Last read at 2:14 PM.",
                            buttons: [PageNotice.Button(id: "close", label: "Close", quiet: true)], dim: true)
    #expect(ReaderCommand.setNotice(notice).javaScript
        == #"window.DotMD.setNotice({"buttons":[{"id":"close","label":"Close","quiet":true}],"dim":true,"icon":"trash","text":"Last read at 2:14 PM.","title":"plan.md was moved or deleted."})"#)
    #expect(ReaderCommand.setNotice(nil).javaScript == "window.DotMD.setNotice(null)")
}
