import AppKit
import Foundation
import Testing
@testable import DotPenRender

@Test func htmlDocumentWrapsBody() {
    let html = HTMLExport.document(bodyHTML: "<h1>Hi</h1>", title: "Plan <draft>", options: ReadingOptions(paper: .night), stylesheet: "body{}")
    #expect(html.hasPrefix("<!doctype html>"))
    #expect(html.contains("<title>Plan &lt;draft&gt;</title>"))
    #expect(html.contains("data-paper=\"night\""))
    #expect(html.contains("<style>body{}</style>"))
    #expect(html.contains("<main id=\"doc\" class=\"doc\"><h1>Hi</h1></main>"))
    #expect(!html.contains("<script"))
}

@Test func inlinesWoff2FontsAsDataURIs() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "fonts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data([0x77, 0x4F, 0x46, 0x32]).write(to: dir.appending(path: "KaTeX_Main-Regular.woff2"))
    let css = "@font-face{src:url(./fonts/KaTeX_Main-Regular.woff2) format(\"woff2\")}"
    let out = HTMLExport.inlineFonts(in: css, fontsDirectory: dir)
    #expect(out.contains("url(data:font/woff2;base64,d09GMg==)"))
    #expect(!out.contains("fonts/"))
}

@Test func inlinesQuotedFontURLs() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "fonts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data([0x77, 0x4F, 0x46, 0x32]).write(to: dir.appending(path: "KaTeX_AMS-Regular.woff2"))
    let css = #"@font-face{src:url("./fonts/KaTeX_AMS-Regular.woff2") format("woff2")}"#
    let out = HTMLExport.inlineFonts(in: css, fontsDirectory: dir)
    #expect(out.contains("url(data:font/woff2;base64,d09GMg==)"))
}

@MainActor
@Test func writesSelfContainedHTMLFile() async throws {
    let controller = ReaderController()
    controller.send(.render(markdown: "# Title\n\nRate $r = n / t$", options: ReadingOptions()))
    #expect(await controller.waitUntilRendered())
    let url = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).html")
    try await HTMLExport.write(from: controller, title: "Title", options: ReadingOptions(), to: url)
    let html = try String(contentsOf: url, encoding: .utf8)
    #expect(html.contains("class=\"katex\""))
    #expect(html.contains("data:font/woff2;base64,"))
    #expect(!html.contains("main.js"))
}

@MainActor
@Test func writesPDFFile() async throws {
    // The print system runs a modal loop that needs an application object, which a bare test process lacks.
    _ = NSApplication.shared
    let controller = ReaderController()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = controller.webView
    controller.send(.render(markdown: "# Title\n\nParagraph", options: ReadingOptions()))
    #expect(await controller.waitUntilRendered())
    let url = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).pdf")
    try await PDFExport.write(webView: controller.webView, to: url)
    let data = try Data(contentsOf: url)
    #expect(data.prefix(4) == Data("%PDF".utf8))
}
