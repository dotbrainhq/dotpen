import AppKit
import WebKit

/// Owns the web view that renders a document and turns its messages into ReaderMessage values.
@MainActor
public final class ReaderController: NSObject {
    public let webView: WKWebView
    public var onMessage: (ReaderMessage) -> () = { _ in }
    private let assetHandler: LocalAssetHandler

    private var isReady = false
    private var pending: [ReaderCommand] = []
    private var rendersSent = 0
    private var rendersDone = 0

    public override init() {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        let assets = LocalAssetHandler()
        configuration.setURLSchemeHandler(assets, forURLScheme: LocalAssetHandler.scheme)
        assetHandler = assets
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        super.init()
        configuration.userContentController.add(WeakScriptHandler(self), name: "dotmd")
        webView.navigationDelegate = self
        webView.underPageBackgroundColor = .clear
        webView.setAccessibilityLabel("Document")
        webView.loadFileURL(RendererResources.indexHTML, allowingReadAccessTo: RendererResources.directory)
    }

    public func send(_ command: ReaderCommand) {
        if case .render = command { rendersSent += 1 }
        guard isReady else {
            pending.append(command)
            return
        }
        webView.evaluateJavaScript(command.javaScript, completionHandler: nil)
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

    public func exportBodyHTML() async throws -> String {
        let value = try await webView.evaluateJavaScript("window.DotMD.exportHTML()")
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
                webView.evaluateJavaScript(command.javaScript, completionHandler: nil)
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
