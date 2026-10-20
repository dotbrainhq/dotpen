import AppKit
import WebKit

public enum ExportError: Error {
    case printFailed
}

/// Paged PDF through the print system, so long documents split into pages with print styles applied.
@MainActor
public enum PDFExport {
    /// Uses the asynchronous runModal(for:) because the synchronous run() deadlocks: WebKit draws the pages
    /// in its own process and needs the main thread free while it does.
    public static func write(webView: WKWebView, to url: URL) async throws {
        guard let window = webView.window,
              let info = NSPrintInfo.shared.copy() as? NSPrintInfo else { throw ExportError.printFailed }
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
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
        guard succeeded else { throw ExportError.printFailed }
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
