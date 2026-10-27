import AppKit
import SwiftUI

/// Opens every reader window as a tab in an open dotPen window, whatever the system tab setting is.
struct WindowTabbing: NSViewRepresentable {
    func makeNSView(context: Context) -> TabbingView { TabbingView() }
    func updateNSView(_ nsView: TabbingView, context: Context) {}

    final class TabbingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.tabbingMode = .preferred
            // SwiftUI shows document windows before this view is attached, so the
            // tabbing mode alone is too late. Join an open window's tab group instead.
            Task { @MainActor [weak window] in
                guard let window, window.tabbedWindows?.count ?? 1 <= 1 else { return }
                let host = NSApp.orderedWindows.first {
                    $0 !== window && $0.isVisible && $0.tabbingMode == .preferred && $0.tabbingIdentifier == window.tabbingIdentifier
                }
                guard let host else { return }
                host.addTabbedWindow(window, ordered: .above)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
