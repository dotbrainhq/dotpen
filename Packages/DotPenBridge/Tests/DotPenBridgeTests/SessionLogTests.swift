import Foundation
import Testing
@testable import DotPenBridge

private func json(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

private var claudeWrite: [String: Any] { [
    "type": "assistant", "sessionId": "s1", "cwd": "/Users/me/code/api-gateway", "timestamp": "2026-10-21T10:00:00.000Z",
    "message": ["content": [
        ["type": "text", "text": "Writing the plan."],
        ["type": "tool_use", "id": "t1", "name": "Write", "input": ["file_path": "/Users/me/code/api-gateway/docs/plan.md", "content": "# Plan"]],
        ["type": "tool_use", "id": "t2", "name": "Edit", "input": ["file_path": "/Users/me/code/api-gateway/README.md", "old_string": "a", "new_string": "b"]],
        ["type": "tool_use", "id": "t3", "name": "Bash", "input": ["command": "ls"]],
    ]],
] }

private func claudeResult(_ id: String, error: Bool = false, at time: String = "2026-10-21T10:00:02.000Z") -> [String: Any] {
    ["type": "user", "sessionId": "s1", "cwd": "/Users/me/code/api-gateway", "timestamp": time,
     "message": ["content": [["type": "tool_result", "tool_use_id": id, "is_error": error, "content": "ok"]]]]
}

@Suite struct ClaudeCodeLogTests {
    @Test func aWriteCountsOnceItSucceeds() {
        var parser = SessionLogParser(agent: .claudeCode)
        #expect(parser.read(line: json(claudeWrite)).isEmpty)
        let writes = parser.read(line: json(claudeResult("t1")))
        #expect(writes == [AgentWrite(agent: .claudeCode, sessionID: "s1", cwd: "/Users/me/code/api-gateway",
                                      path: "/Users/me/code/api-gateway/docs/plan.md", at: SessionLogParser.date("2026-10-21T10:00:02.000Z")!)])
    }

    @Test func aFailedOrNonFileToolWritesNothing() {
        var parser = SessionLogParser(agent: .claudeCode)
        _ = parser.read(line: json(claudeWrite))
        #expect(parser.read(line: json(claudeResult("t2", error: true))).isEmpty)
        #expect(parser.read(line: json(claudeResult("t3"))).isEmpty)
        #expect(parser.read(line: Data("not json".utf8)).isEmpty)
    }

    @Test func everyLineCountsAsActivity() {
        var parser = SessionLogParser(agent: .claudeCode)
        _ = parser.read(line: json(claudeWrite))
        #expect(parser.session == AgentSession(agent: .claudeCode, sessionID: "s1", cwd: "/Users/me/code/api-gateway",
                                               lastActivity: SessionLogParser.date("2026-10-21T10:00:00.000Z")!))
    }
}

@Suite struct CodexLogTests {
    private let meta: [String: Any] = ["timestamp": "2026-10-21T09:00:00.000Z", "type": "session_meta",
                                       "payload": ["id": "c1", "timestamp": "2026-10-21T09:00:00.000Z", "cwd": "/Users/me/code/web-app", "originator": "codex_cli_rs", "cli_version": "0.50.0"]]

    private func patch(_ changes: [String: Any], success: Bool = true) -> [String: Any] {
        ["timestamp": "2026-10-21T09:01:00.000Z", "type": "event_msg",
         "payload": ["type": "patch_apply_end", "call_id": "x", "stdout": "", "stderr": "", "success": success,
                     "changes": changes, "status": success ? "completed" : "failed"]]
    }

    @Test func appliedPatchesNameTheFilesTheyChanged() {
        var parser = SessionLogParser(agent: .codex)
        #expect(parser.read(line: json(meta)).isEmpty)
        let writes = parser.read(line: json(patch([
            "/Users/me/code/web-app/HANDOFF.md": ["type": "update", "unified_diff": "@@", "move_path": NSNull()],
            "docs/guide.md": ["type": "add", "content": "# Guide"],
            "notes/old.md": ["type": "update", "unified_diff": "@@", "move_path": "notes/new.md"],
        ])))
        #expect(Set(writes.map(\.path)) == ["/Users/me/code/web-app/HANDOFF.md", "/Users/me/code/web-app/docs/guide.md",
                                             "/Users/me/code/web-app/notes/new.md"])
        #expect(writes.allSatisfy { $0.sessionID == "c1" && $0.agent == .codex })
    }

    @Test func aFailedPatchWritesNothing() {
        var parser = SessionLogParser(agent: .codex)
        _ = parser.read(line: json(meta))
        #expect(parser.read(line: json(patch(["a.md": ["type": "add", "content": ""]], success: false))).isEmpty)
    }
}

@Suite struct SessionLogTailTests {
    @Test func readsOnlyWholeNewLines() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let first = json(claudeWrite) + Data("\n".utf8)
        let result = json(claudeResult("t1"))
        try (first + result.prefix(20)).write(to: url)
        let tail = SessionLogTail(url: url, agent: .claudeCode, offset: 0)
        #expect(tail.readNew().isEmpty)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: result.dropFirst(20) + Data("\n".utf8))
        try handle.close()
        #expect(tail.readNew().map(\.path) == ["/Users/me/code/api-gateway/docs/plan.md"])
        #expect(tail.readNew().isEmpty)
    }
}

@Suite struct SessionLogFolderTests {
    @Test func recentLogsAreReadFromTheStartAndOldOnesFromTheEnd() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "logs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appending(path: "-Users-me-code-api-gateway")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let lines = json(claudeWrite) + Data("\n".utf8) + json(claudeResult("t1")) + Data("\n".utf8)
        let recent = project.appending(path: "s1.jsonl")
        let old = project.appending(path: "s0.jsonl")
        try lines.write(to: recent)
        try lines.write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-3 * 86400)], ofItemAtPath: old.path)

        let folder = SessionLogFolder(root: root, agent: .claudeCode, recent: 86400)
        #expect(folder.scan().map(\.path) == ["/Users/me/code/api-gateway/docs/plan.md"])
        #expect(folder.scan().isEmpty)

        let handle = try FileHandle(forWritingTo: old)
        try handle.seekToEnd()
        try handle.write(contentsOf: json(claudeWrite) + Data("\n".utf8) + json(claudeResult("t2")) + Data("\n".utf8))
        try handle.close()
        #expect(folder.scan().map(\.path) == ["/Users/me/code/api-gateway/README.md"])
    }

    @Test func codexLogsAreFoundInDateFolders() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let day = root.appending(path: "2026/10/21")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let meta: [String: Any] = ["timestamp": "2026-10-21T09:00:00.000Z", "type": "session_meta", "payload": ["id": "c1", "cwd": "/w"]]
        let patch: [String: Any] = ["timestamp": "2026-10-21T09:01:00.000Z", "type": "event_msg",
                                    "payload": ["type": "patch_apply_end", "success": true, "changes": ["a.md": ["type": "add", "content": ""]]]]
        try (json(meta) + Data("\n".utf8) + json(patch) + Data("\n".utf8)).write(to: day.appending(path: "rollout-2026-10-21T09-00-00-c1.jsonl"))
        try Data("compressed".utf8).write(to: day.appending(path: "rollout-2026-10-20T09-00-00-c0.jsonl.zst"))
        #expect(SessionLogFolder(root: root, agent: .codex, recent: 86400).scan().map(\.path) == ["/w/a.md"])
    }
}
