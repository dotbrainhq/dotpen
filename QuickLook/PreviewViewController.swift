import AppKit
import DotPenRender
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
        controller.send(.render(markdown: text, options: ReadingOptions(), format: SourceFormat(url: url)))
        _ = await controller.waitUntilRendered(timeout: .seconds(3))
    }
}
