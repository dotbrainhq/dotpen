import AppKit
import WebKit

/// Owns the web view that renders a document and turns its messages into ReaderMessage values.
///
/// Each web view keeps a web content process of its own, so a window that has been hidden for `idleDelay` (a
/// background tab or a minimized window) releases its web view. Showing the window again builds a new one, replays
/// the page's state and puts the scroll position back.
@MainActor
public final class ReaderController: NSObject {
    /// Holds the current web view. SwiftUI shows this view, so the web view inside it can be swapped.
    public let container: NSView
    public var onMessage: (ReaderMessage) -> () = { _ in }
    public private(set) var isUnloaded = false
    private let assetHandler: LocalAssetHandler
    private let idleDelay: Duration
    private var loaded: WKWebView?

    private var isReady = false
    private var pending: [ReaderCommand] = []
    private var rendersSent = 0
    private var rendersDone = 0

    /// The last command of each kind that shapes the page, replayed in this order into a new web view.
    private enum Slot: Int, CaseIterable {
        case layout, tasks, render, options, source, comments, panel, notice, memory, marks, writing
    }
    private var state: [Slot: ReaderCommand] = [:]
    private var isVisible = true
    private var idleTask: Task<Void, Never>?
    private var savedScroll: Double?

    /// The live web view. Asking for it while the page is released builds it again.
    public var webView: WKWebView {
        if let loaded { return loaded }
        return load()
    }

    public init(idleDelay: Duration = .seconds(600)) {
        assetHandler = LocalAssetHandler()
        self.idleDelay = idleDelay
        let container = ReaderContainer(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.container = container
        super.init()
        container.controller = self
        load()
    }

    public func send(_ command: ReaderCommand) {
        record(command)
        // A released page gets the command with the rest of its state when it is built again.
        guard let loaded else { return }
        if case .render = command { rendersSent += 1 }
        guard isReady else {
            pending.append(command)
            return
        }
        loaded.evaluateJavaScript(command.javaScript, completionHandler: nil)
    }

    /// Starts or stops the idle countdown. The container calls this when its window is shown or hidden.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        idleTask?.cancel()
        idleTask = nil
        if visible {
            if loaded == nil { load() }
            return
        }
        guard loaded != nil else { return }
        idleTask = Task { [weak self, idleDelay] in
            try? await Task.sleep(for: idleDelay)
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }

    @discardableResult
    private func load() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: LocalAssetHandler.scheme)
        configuration.userContentController.add(WeakScriptHandler(self), name: "dotpen")
        let view = WKWebView(frame: container.bounds, configuration: configuration)
        view.autoresizingMask = [.width, .height]
        view.navigationDelegate = self
        view.underPageBackgroundColor = .clear
        view.setAccessibilityLabel("Document")

        loaded = view
        isUnloaded = false
        isReady = false
        rendersDone = 0
        pending = Slot.allCases.compactMap { state[$0] }
        rendersSent = state[.render] == nil ? 0 : 1
        container.addSubview(view)
        view.loadFileURL(RendererResources.indexHTML, allowingReadAccessTo: RendererResources.directory)

        if let scroll = savedScroll {
            savedScroll = nil
            Task { [weak self] in
                guard let self, await self.waitUntilRendered(timeout: .seconds(10)) else { return }
                _ = try? await self.loaded?.evaluateJavaScript("window.scrollTo(0, \(scroll))")
            }
        }
        return view
    }

    private func unload() async {
        guard let view = loaded else { return }
        let scroll = try? await view.evaluateJavaScript("window.scrollY") as? Double
        // The window may have come back while the scroll position was read.
        guard !isVisible, loaded === view else { return }
        savedScroll = scroll
        view.removeFromSuperview()
        view.navigationDelegate = nil
        view.configuration.userContentController.removeAllScriptMessageHandlers()
        loaded = nil
        isUnloaded = true
        isReady = false
        pending.removeAll()
    }

    private func record(_ command: ReaderCommand) {
        switch command {
        case .render: state[.render] = command
        case .setReadingOptions: state[.options] = command
        case .applyMarks: state[.marks] = command
        case .clearMarks: state[.marks] = nil
        case .setMemory: state[.memory] = command
        case .setWriting: state[.writing] = command
        case .setLayout: state[.layout] = command
        case .setComments: state[.comments] = command
        case .setPanel: state[.panel] = command
        case .setNotice: state[.notice] = command
        case .setTasksEditable: state[.tasks] = command
        case .setSource: state[.source] = command
        // Moments, not state: a glow, a scroll or a jump means nothing on a rebuilt page.
        case .markLive, .reveal, .follow, .nextChange: break
        }
    }

    /// Where relative image paths start, and the folder they may not leave: the watched folder for a library file,
    /// or the file's own folder for a file opened on its own.
    public func setDocumentLocation(_ fileURL: URL?, root: URL?) {
        assetHandler.documentDirectory = fileURL?.deletingLastPathComponent()
        assetHandler.root = root ?? fileURL?.deletingLastPathComponent()
    }

    var assetLocation: (documentDirectory: URL?, root: URL?) {
        (assetHandler.documentDirectory, assetHandler.root)
    }

    /// True once every render sent so far has finished, including Mermaid diagrams.
    public func waitUntilRendered(timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while rendersDone < rendersSent {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    /// Copy for Slack or Google Docs: the page as paste-ready HTML. Diagrams are drawn to images for Docs first,
    /// so the renderer's call is awaited.
    public func copyHTML(for target: CopyTarget) async throws -> String {
        let value = try await webView.callAsyncJavaScript(
            "return await window.dotPen.copyFor(target)", arguments: ["target": target.rawValue], contentWorld: .page
        )
        return value as? String ?? ""
    }

    public func exportBodyHTML() async throws -> String {
        let value = try await webView.evaluateJavaScript("window.dotPen.exportHTML()")
        return value as? String ?? ""
    }

    fileprivate func receive(_ body: Any) {
        guard let message = ReaderMessage(body: body) else { return }
        switch message {
        case .ready:
            isReady = true
            let queued = pending
            pending.removeAll()
            for command in queued {
                loaded?.evaluateJavaScript(command.javaScript, completionHandler: nil)
            }
        case .rendered:
            rendersDone += 1
        default:
            break
        }
        onMessage(message)
    }
}

extension ReaderController: WKNavigationDelegate {
    /// Only the bundled page may load. Links are handled by the renderer and arrive as messages.
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        return url.isFileURL && url.path.hasPrefix(RendererResources.directory.path) ? .allow : .cancel
    }
}

/// Tells the controller when its window is shown or hidden, including a tab moving to the back.
private final class ReaderContainer: NSView {
    weak var controller: ReaderController?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        if let window { center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window) }
        if let newWindow {
            center.addObserver(self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: newWindow)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        occlusionChanged()
    }

    @objc private func occlusionChanged() {
        guard let window else { return }
        controller?.setVisible(window.occlusionState.contains(.visible))
    }
}

/// Breaks the retain cycle between WKUserContentController and the controller.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: ReaderController?

    init(_ target: ReaderController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            target?.receive(message.body)
        }
    }
}

/// Where a copy is headed: Slack's composer has no headings or tables; Google Docs keeps both.
public enum CopyTarget: String, Sendable {
    case slack
    case docs
}
