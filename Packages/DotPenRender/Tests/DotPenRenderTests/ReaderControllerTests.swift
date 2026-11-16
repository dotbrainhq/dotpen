import Foundation
import Testing
import WebKit
@testable import DotPenRender

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

@MainActor
private func eventually(timeout: Duration = .seconds(5), _ condition: () async throws -> Bool) async rethrows -> Bool {
    let deadline = ContinuousClock.now + timeout
    while try await !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

@MainActor
@Test func releasesTheWebViewAfterBeingHiddenForTheIdleDelay() async throws {
    let controller = ReaderController(idleDelay: .milliseconds(100))
    controller.send(.render(markdown: "# Hello", options: ReadingOptions()))
    #expect(await controller.waitUntilRendered())
    controller.setVisible(false)
    #expect(await eventually { controller.isUnloaded })
    #expect(controller.container.subviews.isEmpty)
}

@MainActor
@Test func staysLoadedWhenShownAgainBeforeTheIdleDelay() async throws {
    let controller = ReaderController(idleDelay: .milliseconds(200))
    controller.send(.render(markdown: "# Hello", options: ReadingOptions()))
    #expect(await controller.waitUntilRendered())
    controller.setVisible(false)
    try await Task.sleep(for: .milliseconds(50))
    controller.setVisible(true)
    try await Task.sleep(for: .milliseconds(400))
    #expect(!controller.isUnloaded)
}

@MainActor
@Test func rebuildsThePageWhenShownAgain() async throws {
    let controller = ReaderController(idleDelay: .milliseconds(50))
    controller.send(.render(markdown: "# Hello", options: ReadingOptions()))
    controller.send(.setReadingOptions(ReadingOptions(paper: .night)))
    #expect(await controller.waitUntilRendered())
    let first = controller.webView
    controller.setVisible(false)
    #expect(await eventually { controller.isUnloaded })
    // State that changes while the tab is hidden is kept for the rebuild.
    controller.send(.render(markdown: "# Changed", options: ReadingOptions(paper: .night)))
    controller.setVisible(true)
    #expect(!controller.isUnloaded)
    #expect(controller.webView !== first)
    #expect(controller.container.subviews == [controller.webView])
    #expect(await controller.waitUntilRendered())
    let heading = try await controller.webView.evaluateJavaScript("document.querySelector('h1').textContent") as? String
    #expect(heading == "Changed")
    let paper = try await controller.webView.evaluateJavaScript("document.documentElement.dataset.paper") as? String
    #expect(paper == "night")
}

@MainActor
@Test func restoresTheScrollPositionAfterARebuild() async throws {
    let controller = ReaderController(idleDelay: .milliseconds(50))
    let long = (1...400).map { "Paragraph \($0) with enough words to take a line." }.joined(separator: "\n\n")
    controller.send(.render(markdown: long, options: ReadingOptions()))
    #expect(await controller.waitUntilRendered())
    _ = try await controller.webView.evaluateJavaScript("window.scrollTo(0, 1500)")
    let before = try await controller.webView.evaluateJavaScript("window.scrollY") as? Double ?? 0
    #expect(before > 1000)
    controller.setVisible(false)
    #expect(await eventually { controller.isUnloaded })
    controller.setVisible(true)
    let restored = try await eventually {
        let y = try await controller.webView.evaluateJavaScript("window.scrollY") as? Double ?? 0
        return abs(y - before) < 2
    }
    #expect(restored)
}
