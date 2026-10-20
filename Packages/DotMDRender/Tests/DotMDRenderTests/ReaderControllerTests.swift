import Foundation
import Testing
import WebKit
@testable import DotMDRender

@MainActor
@Test func rendersMarkdownIntoTheWebView() async throws {
    let controller = ReaderController()
    controller.send(.render(markdown: "# Hello\n\nWorld", options: ReadingOptions()))
    #expect(await controller.waitUntilRendered())
    let heading = try await controller.webView.evaluateJavaScript("document.querySelector('h1').textContent") as? String
    #expect(heading == "Hello")
}

@MainActor
@Test func appliesReadingOptions() async throws {
    let controller = ReaderController()
    controller.send(.render(markdown: "Text", options: ReadingOptions()))
    #expect(await controller.waitUntilRendered())
    controller.send(.setReadingOptions(ReadingOptions(size: .large, font: .sans, width: .wide, paper: .night)))
    try await Task.sleep(for: .milliseconds(100))
    let paper = try await controller.webView.evaluateJavaScript("document.documentElement.dataset.paper") as? String
    #expect(paper == "night")
}

@MainActor
@Test func exportsBodyWithoutCopyButtons() async throws {
    let controller = ReaderController()
    controller.send(.render(markdown: "```swift\nlet x = 1\n```", options: ReadingOptions()))
    #expect(await controller.waitUntilRendered())
    let body = try await controller.exportBodyHTML()
    #expect(body.contains("code-block"))
    #expect(!body.contains("class=\"copy\""))
}
