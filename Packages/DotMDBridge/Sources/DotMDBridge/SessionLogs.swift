import Foundation

/// An agent whose session logs DotMD can read to tell who wrote a file.
public enum Agent: String, Codable, Sendable, CaseIterable {
    case claudeCode, codex

    public var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// A file an agent wrote, as its session log records it.
public struct AgentWrite: Equatable, Sendable {
    public var agent: Agent
    public var sessionID: String
    /// The folder the session runs in.
    public var cwd: String
    /// The file's full path.
    public var path: String
    public var at: Date

    public init(agent: Agent, sessionID: String, cwd: String, path: String, at: Date) {
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.path = path
        self.at = at
    }
}

/// A session and when its log last moved.
public struct AgentSession: Equatable, Sendable {
    public var agent: Agent
    public var sessionID: String
    public var cwd: String
    public var lastActivity: Date

    public init(agent: Agent, sessionID: String, cwd: String, lastActivity: Date) {
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.lastActivity = lastActivity
    }
}

/// Reads one session log a line at a time, keeping what earlier lines said about the session.
///
/// Claude Code (`~/.claude/projects/<folder>/<session>.jsonl`): an assistant line asks for Write, Edit, MultiEdit
/// or NotebookEdit with a `file_path`, and a later user line carries its `tool_result`. A write counts once that
/// result arrives without `is_error`, so a refused edit doesn't. Every line has `sessionId`, `cwd` and `timestamp`.
///
/// Codex (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`): each line is `{timestamp, type, payload}`. The
/// `session_meta` line gives the session's `id` and `cwd`; an `event_msg` whose payload type is `patch_apply_end`
/// lists the changed files under `changes`, relative to the cwd or absolute, with `move_path` for renames.
public struct SessionLogParser: Sendable {
    public let agent: Agent
    public private(set) var session: AgentSession?
    /// Claude Code tool calls that write a file, by tool use id, until their result arrives.
    private var pending: [String: String] = [:]

    static let writingTools: Set<String> = ["Write", "Edit", "MultiEdit", "NotebookEdit"]

    public init(agent: Agent) {
        self.agent = agent
    }

    public mutating func read(line: Data) -> [AgentWrite] {
        // Logs run to hundreds of megabytes, mostly tool output. Only lines that can name a write, or set up
        // the session, are decoded.
        guard mayMatter(line), let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return [] }
        let at = (object["timestamp"] as? String).flatMap(Self.date)
        switch agent {
        case .claudeCode: return readClaudeCode(object, at: at)
        case .codex: return readCodex(object, at: at)
        }
    }

    private func mayMatter(_ line: Data) -> Bool {
        if session == nil { return true }
        switch agent {
        case .claudeCode:
            if Self.writingTools.contains(where: { line.range(of: Data("\"name\":\"\($0)\"".utf8)) != nil }) { return true }
            guard !pending.isEmpty, line.range(of: Self.toolResult) != nil else { return false }
            return pending.keys.contains { line.range(of: Data($0.utf8)) != nil }
        case .codex:
            return line.range(of: Self.patchApplyEnd) != nil
        }
    }

    private static let toolResult = Data("\"tool_result\"".utf8)
    private static let patchApplyEnd = Data("\"patch_apply_end\"".utf8)

    private mutating func readClaudeCode(_ object: [String: Any], at: Date?) -> [AgentWrite] {
        if let id = object["sessionId"] as? String, let cwd = object["cwd"] as? String {
            note(sessionID: id, cwd: cwd, at: at)
        }
        let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        var writes: [AgentWrite] = []
        for part in content {
            switch part["type"] as? String {
            case "tool_use":
                guard let name = part["name"] as? String, Self.writingTools.contains(name), let id = part["id"] as? String,
                      let input = part["input"] as? [String: Any],
                      let path = (input["file_path"] ?? input["notebook_path"]) as? String else { continue }
                pending[id] = path
            case "tool_result":
                guard let id = part["tool_use_id"] as? String, let path = pending.removeValue(forKey: id),
                      part["is_error"] as? Bool != true, let session else { continue }
                writes.append(AgentWrite(agent: agent, sessionID: session.sessionID, cwd: session.cwd, path: path,
                                         at: at ?? session.lastActivity))
            default:
                continue
            }
        }
        return writes
    }

    private mutating func readCodex(_ object: [String: Any], at: Date?) -> [AgentWrite] {
        let payload = object["payload"] as? [String: Any] ?? [:]
        switch object["type"] as? String {
        case "session_meta":
            if let id = (payload["id"] ?? payload["session_id"]) as? String, let cwd = payload["cwd"] as? String {
                note(sessionID: id, cwd: cwd, at: at)
            }
            return []
        case "event_msg":
            if let session { note(sessionID: session.sessionID, cwd: session.cwd, at: at) }
            guard payload["type"] as? String == "patch_apply_end", payload["success"] as? Bool == true,
                  let changes = payload["changes"] as? [String: Any], let session else { return [] }
            return changes.keys.sorted().map { key in
                let moved = (changes[key] as? [String: Any])?["move_path"] as? String
                return AgentWrite(agent: agent, sessionID: session.sessionID, cwd: session.cwd,
                                  path: Self.absolute(moved ?? key, in: session.cwd), at: at ?? session.lastActivity)
            }
        default:
            if let session { note(sessionID: session.sessionID, cwd: session.cwd, at: at) }
            return []
        }
    }

    private mutating func note(sessionID: String, cwd: String, at: Date?) {
        let last = at ?? session?.lastActivity ?? .distantPast
        session = AgentSession(agent: agent, sessionID: sessionID, cwd: cwd, lastActivity: max(last, session?.lastActivity ?? .distantPast))
    }

    static func absolute(_ path: String, in cwd: String) -> String {
        path.hasPrefix("/") ? path : URL(fileURLWithPath: cwd).appending(path: path).standardizedFileURL.path
    }

    /// Log timestamps, with or without fractional seconds.
    static func date(_ text: String) -> Date? {
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? fractional.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}

/// One log file, read from where the last read stopped. A line still being written waits for its newline.
public final class SessionLogTail: @unchecked Sendable {
    public let url: URL
    private var offset: UInt64
    private var remainder = Data()
    public private(set) var parser: SessionLogParser
    /// When the file last changed. Lines that aren't decoded still move this.
    private var lastModified: Date?

    /// The session, active as of the file's last change.
    public var session: AgentSession? {
        guard var session = parser.session else { return nil }
        session.lastActivity = max(session.lastActivity, lastModified ?? .distantPast)
        return session
    }

    public init(url: URL, agent: Agent, offset: UInt64) {
        self.url = url
        self.offset = offset
        parser = SessionLogParser(agent: agent)
    }

    public func readNew() -> [AgentWrite] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd(), !data.isEmpty else { return [] }
        offset += UInt64(data.count)
        let buffer = remainder.isEmpty ? data : remainder + data
        var writes: [AgentWrite] = []
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            if newline > start { writes += parser.read(line: buffer[start..<newline]) }
            start = buffer.index(after: newline)
        }
        remainder = Data(buffer[start...])
        if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            lastModified = modified
        }
        return writes
    }
}

/// An agent's log folder. Logs changed in the last `recent` seconds are read from the start, so DotMD knows who
/// wrote what today; older ones from their end, so a resumed session is followed without replaying its history.
/// Compressed Codex logs (`.jsonl.zst`) are old sessions and are skipped.
public final class SessionLogFolder: @unchecked Sendable {
    public let root: URL
    public let agent: Agent
    private let recent: TimeInterval
    private var tails: [String: SessionLogTail] = [:]

    public init(root: URL, agent: Agent, recent: TimeInterval = 86_400) {
        self.root = root
        self.agent = agent
        self.recent = recent
    }

    /// New writes in every log, oldest first.
    public func scan() -> [AgentWrite] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var writes: [AgentWrite] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let path = url.path
            if tails[path] == nil {
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { continue }
                let fresh = (values?.contentModificationDate ?? .distantPast) > Date.now.addingTimeInterval(-recent)
                tails[path] = SessionLogTail(url: url, agent: agent, offset: fresh ? 0 : UInt64(values?.fileSize ?? 0))
            }
            writes += tails[path]?.readNew() ?? []
        }
        return writes.sorted { $0.at < $1.at }
    }

    /// Sessions whose logs moved in the last `window` seconds.
    public func activeSessions(within window: TimeInterval, now: Date = .now) -> [AgentSession] {
        tails.values.compactMap(\.session).filter { now.timeIntervalSince($0.lastActivity) <= window }
    }
}
