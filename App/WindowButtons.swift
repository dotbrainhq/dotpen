import AppKit
import SwiftUI

/// Places the window's close, minimize and zoom buttons where the prototype draws them, measured from the
/// window's top-left corner to the center of the close button. The buttons stay the real system ones.
///
/// AppKit lays the buttons out in the title bar container, so this makes that container tall enough to hold
/// them at the requested height and moves each button, the way Electron's `trafficLightPosition` does.
/// AppKit lays the title bar out again on resize, full screen and title changes, so the placement is applied
/// again whenever the container or a button moves.
struct WindowButtons: NSViewRepresentable {
    /// Center of the close button, in points from the window's top-left corner.
    let closeCenter: CGPoint

    func makeNSView(context: Context) -> PlacementView {
        PlacementView(closeCenter: closeCenter)
    }

    func updateNSView(_ view: PlacementView, context: Context) {
        view.closeCenter = closeCenter
        // A SwiftUI update can change the window title, which makes AppKit lay the title bar out again.
        view.setNeedsPlacement()
    }

    final class PlacementView: NSView {
        var closeCenter: CGPoint {
            didSet { if closeCenter != oldValue { place() } }
        }
        /// The prototype spaces the buttons 20 points apart, center to center: 12 point dots with 8 between.
        private let spacing: CGFloat = 20
        private var observers: [NSObjectProtocol] = []
        /// Title bar views whose frame changes trigger a placement, watched once each.
        private var watchedViews: [ObjectIdentifier] = []
        private var placementPending = false

        init(closeCenter: CGPoint) {
            self.closeCenter = closeCenter
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            watchedViews.removeAll()
            guard let window else { return }
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didBecomeKeyNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place() }
                })
            }
            // After SwiftUI and AppKit finish the first layout pass.
            setNeedsPlacement()
        }

        /// Places the buttons once AppKit finishes the title bar pass in progress, which may move them one at a time.
        func setNeedsPlacement() {
            guard !placementPending else { return }
            placementPending = true
            DispatchQueue.main.async { [weak self] in
                self?.placementPending = false
                self?.place()
            }
        }

        private func place() {
            guard let window, !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let titlebar = close.superview, let container = titlebar.superview else { return }
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
            let height = closeCenter.y * 2
            // Only as wide as the buttons, so the rest of the top edge stays clickable for the app's own controls.
            let width = closeCenter.x + spacing * CGFloat(buttons.count - 1) + closeCenter.x
            let frame = NSRect(x: 0, y: window.frame.height - height, width: width, height: height)
            // Setting only what differs keeps the frame-change observers below from calling back in a loop.
            if container.frame != frame { container.frame = frame }
            for (index, button) in buttons.enumerated() {
                let size = button.frame.size
                let origin = NSPoint(x: closeCenter.x + spacing * CGFloat(index) - size.width / 2, y: (height - size.height) / 2)
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
            for view in [container] + buttons { watch(view) }
        }

        private func watch(_ view: NSView) {
            let id = ObjectIdentifier(view)
            guard !watchedViews.contains(id) else { return }
            watchedViews.append(id)
            view.postsFrameChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setNeedsPlacement() }
            })
        }

    }
}
