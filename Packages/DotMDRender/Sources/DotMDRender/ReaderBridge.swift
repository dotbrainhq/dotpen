import Foundation

/// Which prototype layout the page uses: the Files window with its list showing, or a document on its own.
public enum ReaderLayout: String, Sendable {
    case files, document
}

/// Calls from Swift into window.DotMD in the renderer.
public enum ReaderCommand: Sendable {
    case render(markdown: String, options: ReadingOptions)
    case setReadingOptions(ReadingOptions)
    /// Marks a change set (DotMDCore's ChangeSet) and shows the chip with when the file was last read.
    case applyMarks(changes: any Encodable & Sendable, since: String)
    /// Takes the marks and the chip off, fading them top to bottom when fade is true.
    case clearMarks(fade: Bool)
    /// The dotted line where reading stopped. A nil line removes it.
    case setMemory(line: Int?, label: String)
    /// Blocks an agent just wrote, by start line, for the live-writing glow.
    case markLive(lines: [Int])
    /// The caret while a file is being written, at the end of the last written block.
    case setWriting(Bool, lastLine: Int?)
    case setLayout(ReaderLayout)

    public var javaScript: String {
        switch self {
        case let .render(markdown, options):
            return "window.DotMD.render(\(Self.json(RenderPayload(markdown: markdown, options: options))))"
        case let .setReadingOptions(options):
            return "window.DotMD.setReadingOptions(\(Self.json(options)))"
        case let .applyMarks(changes, since):
            return "window.DotMD.applyMarks(\(Self.json(MarksPayload(changes: changes, since: since))))"
        case let .clearMarks(fade):
            return "window.DotMD.clearMarks(\(fade))"
        case let .setMemory(line, label):
            return "window.DotMD.setMemory(\(Self.json(MemoryPayload(line: line, label: label))))"
        case let .markLive(lines):
            return "window.DotMD.markLive(\(Self.json(lines)))"
        case let .setWriting(writing, lastLine):
            return "window.DotMD.setWriting(\(Self.json(WritingPayload(writing: writing, lastLine: lastLine))))"
        case let .setLayout(layout):
            return "window.DotMD.setLayout(\(Self.json(layout.rawValue)))"
        }
    }

    private struct RenderPayload: Encodable {
        let markdown: String
        let options: ReadingOptions
    }

    private struct MarksPayload: Encodable {
        let changes: any Encodable
        let since: String

        enum CodingKeys: String, CodingKey {
            case changes, since
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(changes, forKey: .changes)
            try container.encode(since, forKey: .since)
        }
    }

    private struct MemoryPayload: Encodable {
        let line: Int?
        let label: String
    }

    private struct WritingPayload: Encodable {
        let writing: Bool
        let lastLine: Int?
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
    /// Mark read in the change chip.
    case markRead
    /// The source line at the top of the view, sent as the person scrolls.
    case scrollLine(Int)

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
        case "markRead": self = .markRead
        case "scrollLine":
            guard let line = (dict["line"] as? Int) ?? (dict["line"] as? NSNumber)?.intValue else { return nil }
            self = .scrollLine(line)
        default:
            return nil
        }
    }
}
