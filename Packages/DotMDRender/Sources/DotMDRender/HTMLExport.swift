import Foundation
import UniformTypeIdentifiers

/// Builds a single HTML file with styles, diagrams (already SVG) and math fonts built in, so it works offline.
public enum HTMLExport {
    public static func document(bodyHTML: String, title: String, options: ReadingOptions, stylesheet: String) -> String {
        """
        <!doctype html>
        <html lang="en" data-size="\(options.size.rawValue)" data-font="\(options.font.rawValue)" data-width="\(options.width.rawValue)" data-paper="\(options.paper.rawValue)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(title))</title>
        <style>\(stylesheet)</style>
        </head>
        <body>
        <main id="doc" class="doc">\(bodyHTML)</main>
        </body>
        </html>
        """
    }

    /// Replaces url(fonts/NAME.woff2) with data URIs. Walks matches from the end so earlier ranges stay valid.
    public static func inlineFonts(in css: String, fontsDirectory: URL) -> String {
        let pattern = #"url\((["']?)(?:\./)?fonts/([^"')]+\.woff2)\1\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return css }
        var result = css
        for match in regex.matches(in: css, range: NSRange(css.startIndex..., in: css)).reversed() {
            guard let whole = Range(match.range, in: result), let nameRange = Range(match.range(at: 2), in: result) else { continue }
            let fileURL = fontsDirectory.appending(path: String(result[nameRange]))
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            result.replaceSubrange(whole, with: "url(data:font/woff2;base64,\(data.base64EncodedString()))")
        }
        return result
    }

    /// Swaps dotmd-asset image URLs for data URIs, so the exported file shows them offline.
    public static func inlineLocalImages(in html: String, documentDirectory: URL?, root: URL?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"dotmd-asset://(?:doc|root)/[^"'\s,)]+"#) else { return html }
        var result = html
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let range = Range(match.range, in: result),
                  let url = URL(string: String(result[range])),
                  let file = LocalAssetHandler.resolve(url, documentDirectory: documentDirectory, root: root),
                  let data = try? Data(contentsOf: file) else { continue }
            result.replaceSubrange(range, with: "data:\(LocalAssetHandler.mimeType(for: file));base64,\(data.base64EncodedString())")
        }
        return result
    }

    @MainActor
    public static func write(from controller: ReaderController, title: String, options: ReadingOptions, to url: URL) async throws {
        let location = controller.assetLocation
        let body = inlineLocalImages(in: try await controller.exportBodyHTML(), documentDirectory: location.documentDirectory, root: location.root)
        let css = try String(contentsOf: RendererResources.stylesheet, encoding: .utf8)
        let html = document(bodyHTML: body, title: title, options: options, stylesheet: inlineFonts(in: css, fontsDirectory: RendererResources.fontsDirectory))
        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
