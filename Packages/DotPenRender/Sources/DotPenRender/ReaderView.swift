import SwiftUI
import WebKit

public struct ReaderView: NSViewRepresentable {
    private let controller: ReaderController

    public init(controller: ReaderController) {
        self.controller = controller
    }

    public func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}
}
