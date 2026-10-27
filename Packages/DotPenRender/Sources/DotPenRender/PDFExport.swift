import AppKit
import WebKit

public enum ExportError: Error {
    case printFailed
}

/// Paged PDF through the print system, so long documents split into pages with print styles applied.
@MainActor
public enum PDFExport {
    public static func write(webView: WKWebView, to url: URL) async throws {
        guard let info = pageInfo() else { throw ExportError.printFailed }
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        guard await run(webView: webView, info: info, showsPanel: false) else { throw ExportError.printFailed }
    }

    /// Print with the system print panel, on the same pages and print styles as the PDF. Cancelling isn't an error.
    public static func print(webView: WKWebView) async {
        guard let info = pageInfo() else { return }
        _ = await run(webView: webView, info: info, showsPanel: true)
    }

    private static func pageInfo() -> NSPrintInfo? {
        guard let info = NSPrintInfo.shared.copy() as? NSPrintInfo else { return nil }
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        return info
    }

    /// Uses the asynchronous runModal(for:) because the synchronous run() deadlocks: WebKit draws the pages
    /// in its own process and needs the main thread free while it does.
    private static func run(webView: WKWebView, info: NSPrintInfo, showsPanel: Bool) async -> Bool {
        guard let window = webView.window else { return false }
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = showsPanel
        operation.showsProgressPanel = showsPanel
        // Without a frame the web view's print view renders blank pages.
        operation.view?.frame = webView.bounds
        var completion: PrintCompletion?
        let succeeded = await withCheckedContinuation { continuation in
            let handler = PrintCompletion(continuation: continuation)
            completion = handler
            operation.runModal(
                for: window,
                delegate: handler,
                didRun: #selector(PrintCompletion.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }
        withExtendedLifetime(completion) {}
        return succeeded
    }
}

/// Receives AppKit's did-run callback for a print operation. AppKit calls it on a background thread,
/// so it is not tied to the main actor and only resumes the continuation, which is safe from any thread.
private final class PrintCompletion: NSObject, Sendable {
    private let continuation: CheckedContinuation<Bool, Never>

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    @objc func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        continuation.resume(returning: success)
    }
}
