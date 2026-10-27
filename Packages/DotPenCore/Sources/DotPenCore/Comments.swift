import CryptoKit
import Foundation
import GRDB

/// A note the person wrote on a passage of a file, for the agent that wrote it.
public struct Comment: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "comment"

    public enum Status: String, Codable, Sendable {
        case open, resolved
    }

    public var id: Int64?
    public var documentID: Int64
    /// The passage the comment points at, as selected on the page.
    public var quote: String
    /// The source lines of the block the passage sits in.
    public var lineStart: Int
    public var lineEnd: Int
    /// A short hash of that block's source, to tell when the text around the passage changed.
    public var contextHash: String
    public var body: String
    public var status: Status
    public var createdAt: Date
    /// When the comment last went to an agent. Nil until it's sent.
    public var sentAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case documentID = "documentId"
        case quote, lineStart, lineEnd, contextHash, body, status, createdAt, sentAt
    }

    enum Fields {
        static let documentID = Column(CodingKeys.documentID)
        static let status = Column(CodingKeys.status)
        static let lineStart = Column(CodingKeys.lineStart)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    public init(documentID: Int64, quote: String, lineStart: Int, lineEnd: Int, contextHash: String, body: String, createdAt: Date = .now) {
        id = nil
        self.documentID = documentID
        self.quote = quote
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.contextHash = contextHash
        self.body = body
        status = .open
        self.createdAt = createdAt
        sentAt = nil
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public var key: Int64 { id ?? 0 }
    /// Open and not yet sent: what the next Send carries. The prototype marks these "In prompt".
    public var isInPrompt: Bool { status == .open && sentAt == nil }
}

/// A comment and where its passage is in the file now: nil when no block shows the passage any more.
public struct PlacedComment: Equatable, Identifiable, Sendable {
    public let comment: Comment
    public let range: LineRange?

    public init(comment: Comment, range: LineRange?) {
        self.comment = comment
        self.range = range
    }

    public var id: Int64 { comment.key }
}

/// Finds where a comment's passage is after the file changes.
public enum CommentAnchor {
    /// The first 12 hex digits of the SHA-256 of a block's whitespace-collapsed source.
    public static func contextHash(of source: String) -> String {
        let collapsed = MarkdownBlocks.collapsingWhitespace(source)
        return SHA256.hash(data: Data(collapsed.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// The block holding a line of the text, for a new comment.
    public static func block(containing line: Int, in text: String) -> MarkdownBlock? {
        MarkdownBlocks.parse(text).last { $0.startLine <= line }.flatMap { $0.endLine >= line ? $0 : nil }
    }

    /// The lines of the block that shows the passage now, the nearest to where it was. Nil when no block shows it.
    public static func locate(quote: String, near line: Int, in text: String) -> LineRange? {
        let passage = MarkdownBlocks.collapsingWhitespace(quote)
        guard !passage.isEmpty else { return nil }
        return MarkdownBlocks.parse(text)
            .filter { $0.words.joined(separator: " ").contains(passage) }
            .min { abs($0.startLine - line) < abs($1.startLine - line) }
            .map { LineRange(start: $0.startLine, end: $0.endLine) }
    }
}

/// Turns comments into the prompt an agent gets: each passage with its lines, then what to do.
public enum PromptBuilder {
    public struct Item: Equatable, Sendable {
        public var lineStart: Int
        public var lineEnd: Int
        public var quote: String
        public var body: String

        public init(lineStart: Int, lineEnd: Int, quote: String, body: String) {
            self.lineStart = lineStart
            self.lineEnd = lineEnd
            self.quote = quote
            self.body = body
        }
    }

    /// Comment text wraps at this many characters, as in the prototype's prompt preview.
    static let width = 46
    /// Longer passages are cut with an ellipsis.
    static let quoteLimit = 80

    /// - Parameters:
    ///   - path: the file's path in its repository, which is where the agent works.
    ///   - noun: what the file is, for the last line: "plan", "spec" or "file".
    ///   - changeNotes: lines from `changeNotes(_:in:)` when the person includes what changed.
    public static func prompt(path: String, noun: String, items: [Item], changeNotes: [String] = []) -> String {
        var parts = ["Review notes on \(path)"]
        for (index, item) in items.enumerated() {
            let lines = lineText(item.lineStart, item.lineEnd)
            let marker = "\(index + 1). "
            let indent = String(repeating: " ", count: marker.count)
            var block = "\(marker)On \(lines), \"\(shortened(item.quote))\""
            for line in wrap(item.body) { block += "\n\(indent)\(line)" }
            parts.append(block)
        }
        if !changeNotes.isEmpty {
            parts.append((["What changed since I last read it:"] + changeNotes.map { "- \($0)" }).joined(separator: "\n"))
        }
        parts.append("Update the \(noun) with these changes, then stop.")
        return parts.joined(separator: "\n\n")
    }

    /// A passage and where it is, for Copy as prompt in the selection bar: the person adds what to do with it.
    public static func reference(path: String, lineStart: Int, lineEnd: Int, quote: String) -> String {
        "In \(path), \(lineText(lineStart, lineEnd)): \"\(shortened(quote))\""
    }

    /// One line per change, with the start of the block it's in.
    public static func changeNotes(_ changes: ChangeSet, in text: String) -> [String] {
        let blocks = MarkdownBlocks.parse(text)
        func excerpt(_ line: Int) -> String {
            guard let block = blocks.first(where: { $0.startLine == line }) else { return "" }
            return " \"" + shortened(block.words.joined(separator: " "), limit: 48) + "\""
        }
        var notes: [(Int, String)] = []
        for range in changes.added { notes.append((range.start, "Added on line \(range.start):" + excerpt(range.start))) }
        for change in changes.changed { notes.append((change.start, "Changed on line \(change.start):" + excerpt(change.start))) }
        for removal in changes.removed {
            let count = removal.lineCount == 1 ? "1 line" : "\(removal.lineCount) lines"
            notes.append((max(removal.afterLine, 1), removal.afterLine == 0 ? "\(count) removed at the top" : "\(count) removed after line \(removal.afterLine)"))
        }
        return notes.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func lineText(_ start: Int, _ end: Int) -> String {
        start == end ? "line \(start)" : "lines \(start)–\(end)"
    }

    static func shortened(_ text: String, limit: Int = quoteLimit) -> String {
        let collapsed = MarkdownBlocks.collapsingWhitespace(text)
        guard collapsed.count > limit else { return collapsed }
        return collapsed.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func wrap(_ text: String) -> [String] {
        var lines: [String] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = ""
            for word in paragraph.split(separator: " ") {
                if line.isEmpty {
                    line = String(word)
                } else if line.count + 1 + word.count <= width {
                    line += " " + word
                } else {
                    lines.append(line)
                    line = String(word)
                }
            }
            lines.append(line)
        }
        return lines
    }
}

extension DocumentKind {
    /// What the prompt's last line calls the file: "Update the plan with these changes, then stop."
    public var promptNoun: String {
        switch self {
        case .plan: "plan"
        case .spec: "spec"
        case .readme: "README"
        case .changelog: "changelog"
        case .agentInstructions: "instructions"
        case .other: "file"
        }
    }
}
