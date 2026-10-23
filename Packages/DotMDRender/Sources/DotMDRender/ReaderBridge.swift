import Foundation

/// Which prototype layout the page uses: the Files window with its list showing, or a document on its own.
public enum ReaderLayout: String, Sendable {
    case files, document
}

/// A comment as the page shows it, beside its passage in the margin.
public struct PageComment: Encodable, Equatable, Sendable {
    public var id: Int64
    /// The first line of the block its passage is in.
    public var line: Int
    public var quote: String
    public var body: String
    /// When it was written, for the card: "now", "2:20 PM" or a date.
    public var when: String
    /// Open and not yet sent: the card says "In prompt" rather than "Sent".
    public var inPrompt: Bool
    /// Its number on the page, beside the passage.
    public var number: Int

    public init(id: Int64, line: Int, quote: String, body: String, when: String, inPrompt: Bool, number: Int) {
        self.id = id
        self.line = line
        self.quote = quote
        self.body = body
        self.when = when
        self.inPrompt = inPrompt
        self.number = number
    }
}

/// The notice above the page: a file that went away (dim shows its last version faded) or a large file shown in part.
public struct PageNotice: Encodable, Equatable, Sendable {
    public struct Button: Encodable, Equatable, Sendable {
        public var id: String
        public var label: String
        public var quiet: Bool

        public init(id: String, label: String, quiet: Bool = false) {
            self.id = id
            self.label = label
            self.quiet = quiet
        }
    }

    /// "trash" or "gauge", the prototype's icons.
    public var icon: String
    public var title: String
    public var text: String
    public var buttons: [Button]
    public var dim: Bool

    public init(icon: String, title: String, text: String, buttons: [Button], dim: Bool = false) {
        self.icon = icon
        self.title = title
        self.text = text
        self.buttons = buttons
        self.dim = dim
    }
}

/// Who writes the comments: the initial in the avatar and the name on each card.
public struct CommentAuthor: Encodable, Equatable, Sendable {
    public var initial: String
    public var name: String

    public init(initial: String, name: String) {
        self.initial = initial
        self.name = name
    }
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
    /// The file's open comments. canComment is false for a file outside the watched folders, which has nowhere to
    /// keep them, so the selection bar leaves Comment out.
    case setComments([PageComment], author: CommentAuthor, canComment: Bool)
    /// The comments panel takes the right of the window, and the margin's cards hide behind it.
    case setPanel(Bool)
    /// Scrolls a block into view and flashes it, for a comment chosen in the panel.
    case reveal(line: Int)
    /// Keeps the block an agent just wrote in view, while the person follows along.
    case follow(line: Int)
    /// Goes to the next change, as N does. Review Changes in the finished pill uses it.
    case nextChange
    /// The notice above the page, or none.
    case setNotice(PageNotice?)
    /// Task boxes tick, for a file DotMD may write to. Off by default, as in Quick Look.
    case setTasksEditable(Bool)
    /// Show Source: the file as written instead of the page.
    case setSource(Bool)

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
        case let .setComments(items, author, canComment):
            return "window.DotMD.setComments(\(Self.json(CommentsPayload(items: items, author: author, canComment: canComment))))"
        case let .setPanel(open):
            return "window.DotMD.setPanel(\(open))"
        case let .reveal(line):
            return "window.DotMD.reveal(\(line))"
        case let .follow(line):
            return "window.DotMD.follow(\(line))"
        case .nextChange:
            return "window.DotMD.nextChange()"
        case let .setNotice(notice):
            return notice.map { "window.DotMD.setNotice(\(Self.json($0)))" } ?? "window.DotMD.setNotice(null)"
        case let .setTasksEditable(editable):
            return "window.DotMD.setTasksEditable(\(editable))"
        case let .setSource(on):
            return "window.DotMD.setSource(\(on))"
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

    private struct CommentsPayload: Encodable {
        let items: [PageComment]
        let author: CommentAuthor
        let canComment: Bool
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
    /// Comment ⌘↩ in the composer: a new comment on a passage, or an edit when id is set.
    case saveComment(line: Int, quote: String, body: String, id: Int64?)
    case resolveComment(id: Int64)
    /// Copy as prompt in the selection bar: the passage and where it is.
    case copyPrompt(line: Int, quote: String)
    /// A comment composer gained or lost focus. While it has it, ⌘↩ belongs to the composer.
    case composing(Bool)
    /// F on the page: start or stop following the agent writing the file.
    case toggleFollow
    /// ? on the page: the keyboard shortcuts overlay.
    case showShortcuts
    /// A button in the notice above the page, by its id.
    case noticeAction(String)
    /// A task box clicked or ticked with Space, by its item's source line.
    case toggleTask(line: Int, checked: Bool)
    /// J or K on the page: the next or previous file in the list.
    case stepFile(Int)

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
        case "saveComment":
            guard let line = (dict["line"] as? NSNumber)?.intValue, let quote = dict["quote"] as? String,
                  let body = dict["body"] as? String else { return nil }
            self = .saveComment(line: line, quote: quote, body: body, id: (dict["id"] as? NSNumber)?.int64Value)
        case "resolveComment":
            guard let id = (dict["id"] as? NSNumber)?.int64Value else { return nil }
            self = .resolveComment(id: id)
        case "toggleFollow": self = .toggleFollow
        case "showShortcuts": self = .showShortcuts
        case "noticeAction":
            guard let id = dict["id"] as? String else { return nil }
            self = .noticeAction(id)
        case "toggleTask":
            guard let line = (dict["line"] as? NSNumber)?.intValue, let checked = dict["checked"] as? Bool else { return nil }
            self = .toggleTask(line: line, checked: checked)
        case "stepFile":
            guard let by = (dict["by"] as? NSNumber)?.intValue else { return nil }
            self = .stepFile(by)
        case "composing":
            guard let active = dict["active"] as? Bool else { return nil }
            self = .composing(active)
        case "copyPrompt":
            guard let line = (dict["line"] as? NSNumber)?.intValue, let quote = dict["quote"] as? String else { return nil }
            self = .copyPrompt(line: line, quote: quote)
        default:
            return nil
        }
    }
}
