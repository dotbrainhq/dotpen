import SwiftUI
import WebKit

public struct ReaderView: NSViewRepresentable {
    private let controller: ReaderController

    public init(controller: ReaderController) {
        self.controller = controller
    }

    public func makeNSView(context: Context) -> NSView {
        controller.container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}
