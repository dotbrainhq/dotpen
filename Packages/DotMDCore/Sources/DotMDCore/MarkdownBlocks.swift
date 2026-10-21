import Foundation
import Markdown

/// One block of a Markdown file as the reader shows it: a heading, paragraph, list item, table and so on.
public struct MarkdownBlock: Equatable, Sendable {
    /// The first line, counted from 1 the way the renderer's data-line is.
    public var startLine: Int
    /// The last line with content.
    public var endLine: Int
    public var source: String
    /// The source with whitespace collapsed, for matching blocks across versions.
    public var key: String
    /// The text the page shows, split on whitespace. Checkbox markers, image alt text and raw HTML aren't shown.
    /// Filled by `parse`; the diff fills it only for blocks it has to compare word by word.
    public var words: [String]
}

public enum MarkdownBlocks {
    /// Top-level blocks in reading order, with their words. Lists split into their top-level items, as the
    /// renderer tags them.
    public static func parse(_ text: String) -> [MarkdownBlock] {
        let parsed = outline(text)
        return zip(parsed.blocks, parsed.markups).map { block, markup in
            var block = block
            block.words = words(of: markup)
            return block
        }
    }

    /// The blocks without their words, and the parsed node behind each, for callers that only need words for some.
    static func outline(_ text: String) -> (blocks: [MarkdownBlock], markups: [Markup]) {
        let body = blankingFrontMatter(text.replacingOccurrences(of: "\r\n", with: "\n"))
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        var blocks: [MarkdownBlock] = []
        var markups: [Markup] = []
        func add(_ markup: Markup) {
            guard let block = makeBlock(markup, lines: lines) else { return }
            blocks.append(block)
            markups.append(markup)
        }
        // Qualified: DotMDCore has its own Document, the database row.
        for child in Markdown.Document(parsing: body).children {
            if let list = child as? ListItemContainer {
                list.listItems.forEach(add)
            } else {
                add(child)
            }
        }
        return (blocks, markups)
    }

    static func words(of markup: Markup) -> [String] {
        var text = PageText()
        text.visit(markup)
        return text.value.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Replaces front matter with the same number of blank lines, as the renderer does, so lines below it stay true.
    public static func blankingFrontMatter(_ text: String) -> String {
        guard let match = text.prefixMatch(of: /---\n[\s\S]*?\n---[ \t]*(?:\n|$)/) else { return text }
        let front = String(match.output)
        let newlines = front.filter { $0 == "\n" }.count
        let lineCount = front.hasSuffix("\n") ? newlines : newlines + 1
        return String(repeating: "\n", count: lineCount) + text[match.range.upperBound...]
    }

    private static func makeBlock(_ markup: Markup, lines: [Substring]) -> MarkdownBlock? {
        guard let range = markup.range else { return nil }
        let start = range.lowerBound.line
        var end = min(range.upperBound.line, lines.count)
        while end > start, lines[end - 1].allSatisfy(\.isWhitespace) { end -= 1 }
        guard start >= 1, start <= end else { return nil }
        let source = lines[(start - 1)..<end].joined(separator: "\n")
        return MarkdownBlock(startLine: start, endLine: end, source: source, key: collapsingWhitespace(source), words: [])
    }

    /// Runs of spaces, tabs and newlines become one space. Works on bytes: this runs for every block of a file.
    static func collapsingWhitespace(_ text: String) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count)
        var pendingSpace = false
        for byte in text.utf8 {
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                pendingSpace = !out.isEmpty
            } else {
                if pendingSpace { out.append(0x20) }
                pendingSpace = false
                out.append(byte)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }
}

/// Collects the text a block shows on the page.
private struct PageText: MarkupWalker {
    var value = ""

    mutating func visitText(_ text: Text) { value += text.string }
    mutating func visitInlineCode(_ inlineCode: InlineCode) { value += inlineCode.code }
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) { value += codeBlock.code }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { value += " " }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { value += " " }
    // Alt text and raw HTML aren't part of the page's text.
    mutating func visitImage(_ image: Image) {}
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {}
    mutating func visitHTMLBlock(_ html: HTMLBlock) {}
    // Blocks inside a block, like a nested paragraph or a table cell, are separate words.
    mutating func visitParagraph(_ paragraph: Paragraph) {
        descendInto(paragraph)
        value += " "
    }
    mutating func visitTableCell(_ cell: Table.Cell) {
        descendInto(cell)
        value += " "
    }
}
