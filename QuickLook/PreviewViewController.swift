import AppKit
import DotMDRender
import QuickLookUI

final class PreviewViewController: NSViewController {
    private let controller = ReaderController()

    override func loadView() {
        view = controller.webView
    }
}

extension PreviewViewController: @preconcurrency QLPreviewingController {
    func preparePreviewOfFile(at url: URL) async throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        controller.send(.render(markdown: text, options: ReadingOptions()))
        _ = await controller.waitUntilRendered(timeout: .seconds(3))
    }
}
