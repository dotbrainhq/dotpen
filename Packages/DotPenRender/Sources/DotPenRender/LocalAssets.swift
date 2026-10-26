import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves images a document links by relative path. "doc" paths start at the document's folder,
/// "root" paths at the watched folder. Only images inside the root are served.
@MainActor
final class LocalAssetHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "dotpen-asset"
    nonisolated static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "avif", "bmp", "tif", "tiff", "ico"]

    var documentDirectory: URL?
    var root: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let file = Self.resolve(url, documentDirectory: documentDirectory, root: root),
              let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: Self.mimeType(for: file), expectedContentLength: data.count, textEncodingName: nil))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    nonisolated static func resolve(_ url: URL, documentDirectory: URL?, root: URL?) -> URL? {
        guard url.scheme == scheme, let root else { return nil }
        guard let base = url.host() == "root" ? root : documentDirectory else { return nil }
        let relativePath = url.path(percentEncoded: false).drop { $0 == "/" }
        let file = base.appending(path: String(relativePath)).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard file.path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/"),
              imageExtensions.contains(file.pathExtension.lowercased()) else { return nil }
        // A symlink inside the folder could point anywhere, so the real paths have to agree too.
        let realRoot = root.resolvingSymlinksInPath().path
        guard file.resolvingSymlinksInPath().path.hasPrefix(realRoot + "/") else { return nil }
        return file
    }

    nonisolated static func mimeType(for file: URL) -> String {
        UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}
