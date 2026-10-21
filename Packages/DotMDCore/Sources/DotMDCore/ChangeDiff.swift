import Foundation

public struct LineRange: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// One step through a changed block's words, in order.
public struct WordOp: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case keep, insert, delete
    }

    public var kind: Kind
    /// How many of the current block's words are kept or inserted. 0 for a delete.
    public var count: Int
    /// The deleted words, for a delete.
    public var text: String?

    public init(kind: Kind, count: Int, text: String?) {
        self.kind = kind
        self.count = count
        self.text = text
    }
}

public struct ChangedBlock: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var words: [WordOp]
}

public struct Removal: Codable, Equatable, Sendable {
    /// The start line of the current block the removed lines followed. 0 when they were at the top.
    public var afterLine: Int
    public var lineCount: Int
    public var text: String

    public init(afterLine: Int, lineCount: Int, text: String) {
        self.afterLine = afterLine
        self.lineCount = lineCount
        self.text = text
    }
}

/// What changed in a file since the person last read it, keyed by line in the current text.
public struct ChangeSet: Codable, Equatable, Sendable {
    public var added: [LineRange] = []
    public var changed: [ChangedBlock] = []
    public var removed: [Removal] = []

    public init() {}

    public var count: Int { added.count + changed.count + removed.count }
    public var isEmpty: Bool { count == 0 }

    /// The start line of every change in reading order. A removal at the top counts as line 1.
    public var lines: [Int] {
        Array(Set(added.map(\.start) + changed.map(\.start) + removed.map { max($0.afterLine, 1) })).sorted()
    }
}

public enum ChangeDiff {
    /// Blocks pair up as one changed block when their words overlap at least this much.
    static let pairingSimilarity = 0.5
    /// Past this many cells a longest common subsequence costs too much; the run is treated as replaced.
    static let blockTableLimit = 4_000_000
    static let wordTableLimit = 1_000_000

    public static func changes(from old: String, to new: String) -> ChangeSet {
        let before = MarkdownBlocks.outline(old)
        let after = MarkdownBlocks.outline(new)
        return diff(before.blocks, after.blocks) { side, index in
            MarkdownBlocks.words(of: side == .old ? before.markups[index] : after.markups[index])
        }
    }

    enum Side { case old, new }

    /// `words` gives a block's words by side and index; only blocks outside the matched ends are asked for.
    static func diff(_ old: [MarkdownBlock], _ new: [MarkdownBlock], words: (Side, Int) -> [String] = { _, _ in [] }) -> ChangeSet {
        var result = ChangeSet()
        // Most edits touch the middle of a file, so the matching ends are set aside first.
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix].key == new[prefix].key { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix].key == new[new.count - 1 - suffix].key { suffix += 1 }
        var oldMiddle = Array(old[prefix..<(old.count - suffix)])
        var newMiddle = Array(new[prefix..<(new.count - suffix)])
        let pairs = matchedPairs(oldMiddle, newMiddle)
        // Words only matter for blocks that didn't match, which are usually few.
        let matchedOld = Set(pairs.map(\.0))
        let matchedNew = Set(pairs.map(\.1))
        for i in oldMiddle.indices where !matchedOld.contains(i) && oldMiddle[i].words.isEmpty {
            oldMiddle[i].words = words(.old, prefix + i)
        }
        for j in newMiddle.indices where !matchedNew.contains(j) && newMiddle[j].words.isEmpty {
            newMiddle[j].words = words(.new, prefix + j)
        }

        var before = prefix > 0 ? new[prefix - 1].startLine : 0
        var oldIndex = 0
        var newIndex = 0
        for (i, j) in pairs + [(oldMiddle.count, newMiddle.count)] {
            resolve(Array(oldMiddle[oldIndex..<i]), Array(newMiddle[newIndex..<j]), after: before, into: &result)
            if j < newMiddle.count { before = newMiddle[j].startLine }
            oldIndex = i + 1
            newIndex = j + 1
        }
        return result
    }

    /// Index pairs of blocks with equal keys, in order: a longest common subsequence.
    private static func matchedPairs(_ old: [MarkdownBlock], _ new: [MarkdownBlock]) -> [(Int, Int)] {
        guard !old.isEmpty, !new.isEmpty, old.count * new.count <= blockTableLimit else { return [] }
        let table = suffixTable(old.map(\.key), new.map(\.key))
        var pairs: [(Int, Int)] = []
        var i = 0
        var j = 0
        let width = new.count + 1
        while i < old.count, j < new.count {
            if old[i].key == new[j].key {
                pairs.append((i, j))
                i += 1
                j += 1
            } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }

    /// table[i * (b.count + 1) + j] is the length of the longest common subsequence of a[i...] and b[j...].
    private static func suffixTable<T: Equatable>(_ a: [T], _ b: [T]) -> [Int32] {
        let width = b.count + 1
        var table = [Int32](repeating: 0, count: (a.count + 1) * width)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i * width + j] = a[i] == b[j]
                    ? table[(i + 1) * width + j + 1] + 1
                    : max(table[(i + 1) * width + j], table[i * width + j + 1])
            }
        }
        return table
    }

    /// A run of old blocks replaced by a run of new ones. In order, each new block pairs with the next old block
    /// similar enough to be the same block rewritten; old blocks skipped over or left at the end were removed.
    private static func resolve(_ old: [MarkdownBlock], _ new: [MarkdownBlock], after: Int, into result: inout ChangeSet) {
        guard !old.isEmpty || !new.isEmpty else { return }
        var position = after
        var nextOld = 0
        for block in new {
            if let match = (nextOld..<old.count).first(where: { similarity(old[$0], block) >= pairingSimilarity }) {
                appendRemoval(old[nextOld..<match], after: position, into: &result)
                result.changed.append(ChangedBlock(start: block.startLine, end: block.endLine, words: wordOps(old[match].words, block.words)))
                nextOld = match + 1
            } else {
                result.added.append(LineRange(start: block.startLine, end: block.endLine))
            }
            position = block.startLine
        }
        appendRemoval(old[nextOld...], after: position, into: &result)
    }

    private static func appendRemoval(_ blocks: ArraySlice<MarkdownBlock>, after: Int, into result: inout ChangeSet) {
        guard !blocks.isEmpty else { return }
        result.removed.append(Removal(
            afterLine: after,
            lineCount: blocks.reduce(0) { $0 + $1.endLine - $1.startLine + 1 },
            text: blocks.map(\.source).joined(separator: "\n\n")
        ))
    }

    /// The Dice coefficient of the two blocks' word sets, ignoring case.
    private static func similarity(_ a: MarkdownBlock, _ b: MarkdownBlock) -> Double {
        let left = Set(a.words.map { $0.lowercased() })
        let right = Set(b.words.map { $0.lowercased() })
        guard !left.isEmpty || !right.isEmpty else { return 0 }
        return 2 * Double(left.intersection(right).count) / Double(left.count + right.count)
    }

    /// Steps through the new block's words: kept, inserted, or (before an insert) old words deleted.
    static func wordOps(_ old: [String], _ new: [String]) -> [WordOp] {
        guard old.count * new.count <= wordTableLimit else {
            return merged([WordOp(kind: .delete, count: 0, text: old.joined(separator: " ")), WordOp(kind: .insert, count: new.count, text: nil)])
        }
        let table = suffixTable(old, new)
        let width = new.count + 1
        var ops: [WordOp] = []
        var deleted: [String] = []
        func flushDeleted() {
            if !deleted.isEmpty { ops.append(WordOp(kind: .delete, count: 0, text: deleted.joined(separator: " "))) }
            deleted.removeAll()
        }
        var i = 0
        var j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, old[i] == new[j] {
                flushDeleted()
                ops.append(WordOp(kind: .keep, count: 1, text: nil))
                i += 1
                j += 1
            } else if i < old.count, j == new.count || table[(i + 1) * width + j] >= table[i * width + j + 1] {
                deleted.append(old[i])
                i += 1
            } else {
                flushDeleted()
                ops.append(WordOp(kind: .insert, count: 1, text: nil))
                j += 1
            }
        }
        flushDeleted()
        return merged(ops)
    }

    /// Joins neighboring keeps and inserts into one step each. Deletes are already whole runs.
    private static func merged(_ ops: [WordOp]) -> [WordOp] {
        var out: [WordOp] = []
        for op in ops {
            if op.kind == .delete, op.text?.isEmpty != false { continue }
            if let last = out.last, last.kind == op.kind, op.kind != .delete {
                out[out.count - 1].count += op.count
            } else {
                out.append(op)
            }
        }
        return out
    }
}
