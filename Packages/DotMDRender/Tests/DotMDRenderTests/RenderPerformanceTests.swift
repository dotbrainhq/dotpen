import Foundation
import Testing
@testable import DotMDRender

/// The spec's budget: open a 1 MB file in under 300 ms. Runs only with DOTMD_PERF=1, so CI stays fast.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["DOTMD_PERF"] == "1"))
func rendersAMegabyteFileInUnderThreeHundredMilliseconds() async {
    let controller = ReaderController()
    let paragraph = "The bucket refills at a steady rate and every request takes one token from it. "
    let markdown = (0..<4_000).map { "## Section \($0)\n\n" + String(repeating: paragraph, count: 3) }.joined(separator: "\n\n")
    #expect(markdown.utf8.count > 1_000_000)
    controller.send(.render(markdown: "# Warm up", options: ReadingOptions()))
    _ = await controller.waitUntilRendered(timeout: .seconds(10))
    let elapsed = await ContinuousClock().measure {
        controller.send(.render(markdown: markdown, options: ReadingOptions()))
        _ = await controller.waitUntilRendered(timeout: .seconds(10))
    }
    #expect(elapsed < .milliseconds(300), "Rendering took \(elapsed)")
}
