import Foundation

/// Calls from Swift into window.DotMD in the renderer.
public enum ReaderCommand: Sendable {
    case render(markdown: String, options: ReadingOptions)
    case setReadingOptions(ReadingOptions)

    public var javaScript: String {
        switch self {
        case let .render(markdown, options):
            return "window.DotMD.render(\(Self.json(RenderPayload(markdown: markdown, options: options))))"
        case let .setReadingOptions(options):
            return "window.DotMD.setReadingOptions(\(Self.json(options)))"
        }
    }

    private struct RenderPayload: Encodable {
        let markdown: String
        let options: ReadingOptions
    }

    /// JSON is a valid JavaScript literal, so the content needs no other escaping.
    /// "</" becomes "<\/" (a legal JSON escape) so no string can close a script element.
    private static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "</", with: "<\\/")
    }
}

/// Messages the renderer posts to the "dotmd" handler.
public enum ReaderMessage: Equatable, Sendable {
    case ready
    case rendered
    case linkActivated(String)
    case copyText(String)
    case diagramError(line: Int, message: String)

    public init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready": self = .ready
        case "rendered": self = .rendered
        case "linkActivated":
            guard let href = dict["href"] as? String else { return nil }
            self = .linkActivated(href)
        case "copyText":
            guard let text = dict["text"] as? String else { return nil }
            self = .copyText(text)
        case "diagramError":
            let line = (dict["line"] as? Int) ?? (dict["line"] as? NSNumber)?.intValue ?? 0
            self = .diagramError(line: line, message: dict["message"] as? String ?? "")
        default:
            return nil
        }
    }
}
