import Foundation
import Testing
@testable import DotPenBridge

/// Two comments in api-gateway, held in memory.
actor FakeSource: CommentSource {
    var comments = [
        BridgeComment(id: 1, path: "/Users/me/code/api-gateway/docs/plans/rate-limiter.md", relativePath: "docs/plans/rate-limiter.md",
                      lineStart: 14, lineEnd: 14, quote: "Roll out to internal keys for one day", body: "One day is enough."),
        BridgeComment(id: 2, path: "/Users/me/code/api-gateway/README.md", relativePath: "README.md",
                      lineStart: 3, lineEnd: 5, quote: "Run make dev", body: "Say which port it uses."),
    ]

    func openComments() -> [BridgeComment] { comments }

    func resolve(id: Int64) -> Bool {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return false }
        comments.remove(at: index)
        return true
    }
}

/// Review requests held in memory: path → id, and a status per id.
actor FakeReviews: ReviewSource {
    var requested: [(path: String, note: String?)] = []
    var statuses: [Int64: ReviewStatus] = [:]

    func requestReview(path: String, note: String?) -> Int64? {
        guard path.hasSuffix("rate-limiter.md") else { return nil }
        requested.append((path, note))
        let id = Int64(requested.count)
        statuses[id] = .pending
        return id
    }

    func reviewStatus(id: Int64) -> ReviewStatus { statuses[id] ?? .unknown }

    func finish(_ id: Int64, comments: [BridgeComment]) { statuses[id] = .done(comments) }
}

actor Names {
    var all: [String] = []
    func add(_ name: String) { all.append(name) }
}

private func call(_ tools: MCPTools, _ name: String, _ arguments: [String: Any] = [:]) async -> (text: String, isError: Bool) {
    let response = await tools.respond(to: ["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": name, "arguments": arguments]])
    let result = response?["result"] as? [String: Any]
    let content = result?["content"] as? [[String: Any]]
    return (content?.first?["text"] as? String ?? "", result?["isError"] as? Bool ?? false)
}

@Suite struct MCPToolsTests {
    let source = FakeSource()
    var tools: MCPTools { MCPTools(source: source, version: "0.1.0") }

    @Test func initializeAnswersWithTheToolsCapability() async throws {
        let response = try #require(await tools.respond(to: ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                                             "params": ["protocolVersion": "2025-03-26"]]))
        let result = try #require(response["result"] as? [String: Any])
        #expect(response["id"] as? Int == 1)
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "dotpen")
    }

    @Test func initializeNamesDotPenWithItsIcon() async throws {
        let tools = MCPTools(source: source, version: "0.1.0", icon: Data([0x89, 0x50, 0x4E, 0x47]))
        let response = try #require(await tools.respond(to: ["jsonrpc": "2.0", "id": 1, "method": "initialize"]))
        let info = try #require((response["result"] as? [String: Any])?["serverInfo"] as? [String: Any])
        #expect(info["title"] as? String == "dotPen")
        #expect((info["description"] as? String)?.isEmpty == false)
        let icon = try #require((info["icons"] as? [[String: Any]])?.first)
        #expect(icon["src"] as? String == "data:image/png;base64,iVBORw==")
        #expect(icon["mimeType"] as? String == "image/png")
        #expect(icon["sizes"] as? [String] == ["128x128"])
    }

    @Test func initializeNamesTheAgentThatConnected() async {
        let names = Names()
        let tools = MCPTools(source: source, version: "0.1.0") { name in Task { await names.add(name) } }
        _ = await tools.respond(to: ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                     "params": ["clientInfo": ["name": "claude-code", "version": "2.1"]]])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await names.all == ["Claude Code"])
        #expect(MCPTools.agentName(forClient: "codex-mcp-client") == "Codex")
        #expect(MCPTools.agentName(forClient: "gemini-cli-mcp-client") == "Gemini CLI")
        #expect(MCPTools.agentName(forClient: "grok-cli") == "Grok CLI")
        #expect(MCPTools.agentName(forClient: "my-agent") == "my-agent")
    }

    @Test func notificationsGetNoResponse() async {
        #expect(await tools.respond(to: ["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil)
    }

    @Test func unknownMethodsAreErrors() async throws {
        let response = try #require(await tools.respond(to: ["jsonrpc": "2.0", "id": "a", "method": "resources/list"]))
        #expect((response["error"] as? [String: Any])?["code"] as? Int == -32601)
        #expect(response["id"] as? String == "a")
    }

    @Test func listsTheThreeTools() async throws {
        let response = try #require(await tools.respond(to: ["jsonrpc": "2.0", "id": 2, "method": "tools/list"]))
        let list = try #require((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(list.compactMap { $0["name"] as? String } == ["list_comments", "get_comments", "resolve_comment"])
    }

    @Test func getCommentsMatchesThePathAnAgentPasses() async {
        for path in ["docs/plans/rate-limiter.md", "./docs/plans/rate-limiter.md",
                     "/Users/me/code/api-gateway/docs/plans/rate-limiter.md", "api-gateway/docs/plans/rate-limiter.md"] {
            let (text, isError) = await call(tools, "get_comments", ["path": path])
            #expect(!isError)
            #expect(text.hasPrefix("Comment 1 on docs/plans/rate-limiter.md, line 14\n"), "\(path)")
            #expect(!text.contains("Comment 2"))
        }
        #expect(await call(tools, "get_comments", ["path": "docs/other.md"]).text == "No open comments.")
        #expect(await call(tools, "get_comments").isError)
    }

    @Test func listCommentsDescribesEachOne() async {
        let (text, _) = await call(tools, "list_comments")
        #expect(text == """
        Comment 1 on docs/plans/rate-limiter.md, line 14
        Passage: "Roll out to internal keys for one day"
        Comment: One day is enough.
        File: /Users/me/code/api-gateway/docs/plans/rate-limiter.md

        Comment 2 on README.md, lines 3-5
        Passage: "Run make dev"
        Comment: Say which port it uses.
        File: /Users/me/code/api-gateway/README.md
        """)
    }

    @Test func resolveCommentResolvesOnce() async {
        #expect(await call(tools, "resolve_comment", ["id": 2]) == ("Resolved comment 2.", false))
        #expect(await call(tools, "resolve_comment", ["id": 2]) == ("No open comment 2.", true))
        #expect(await source.comments.map(\.id) == [1])
    }
}

@Suite struct HTTPTests {
    @Test func parsesARequestOnceItsBodyArrives() {
        let head = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:47319\r\nContent-Type: application/json\r\nContent-Length: 4\r\n\r\n"
        #expect(HTTPRequest.parse(Data("POST /mcp HTTP/1.1\r\nHost: 127".utf8)) == .incomplete)
        #expect(HTTPRequest.parse(Data((head + "{}").utf8)) == .incomplete)
        #expect(HTTPRequest.parse(Data((head + "{  }").utf8)) == .complete(HTTPRequest(
            method: "POST", path: "/mcp",
            headers: ["host": "127.0.0.1:47319", "content-type": "application/json", "content-length": "4"],
            body: Data("{  }".utf8))))
        #expect(HTTPRequest.parse(Data("nonsense\r\n\r\n".utf8)) == .invalid)
    }

    @Test func onlyLocalHostsAreLocal() {
        #expect(BridgeServer.isLocal(host: "127.0.0.1:47319"))
        #expect(BridgeServer.isLocal(host: "localhost"))
        #expect(BridgeServer.isLocal(host: "[::1]:47319"))
        #expect(!BridgeServer.isLocal(host: "evil.example:47319"))
        #expect(!BridgeServer.isLocal(host: nil))
    }
}

@Suite struct BridgeServerTests {
    private func post(_ port: UInt16, _ body: String, headers: [String: String] = [:], method: String = "POST") async throws -> (Int, [String: Any]?) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        request.httpMethod = method
        if method == "POST" { request.httpBody = Data(body.utf8) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as! HTTPURLResponse).statusCode, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func answersMCPOverHTTPOnTheLoopback() async throws {
        let server = BridgeServer(tools: MCPTools(source: FakeSource(), version: "0.1.0"))
        let port = try await server.start(port: 0)
        defer { server.stop() }

        let (status, body) = try await post(port, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#)
        #expect(status == 200)
        #expect((body?["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18")

        #expect(try await post(port, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#).0 == 202)

        let (_, list) = try await post(port, #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_comments","arguments":{"path":"README.md"}}}"#)
        let content = ((list?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String
        #expect(content?.hasPrefix("Comment 2 on README.md") == true)

        #expect(try await post(port, "", method: "GET").0 == 405)
        #expect(try await post(port, "{", headers: [:]).0 == 400)
        #expect(try await post(port, #"{"jsonrpc":"2.0","id":3,"method":"ping"}"#, headers: ["Origin": "https://evil.example"]).0 == 403)
    }
}

@Suite struct ReviewToolsTests {
    let reviews = FakeReviews()
    var tools: MCPTools { MCPTools(source: FakeSource(), reviews: reviews, version: "0.1.0", reviewPollInterval: .milliseconds(10)) }

    @Test func reviewToolsAreListedOnlyWhenTheAppOffersThem() async throws {
        let names = { (tools: MCPTools) async throws -> [String] in
            let response = try #require(await tools.respond(to: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"]))
            return ((response["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        }
        #expect(try await names(tools) == ["list_comments", "get_comments", "resolve_comment", "request_review", "wait_for_review"])
        #expect(try await names(MCPTools(source: FakeSource(), version: "0.1.0")) == ["list_comments", "get_comments", "resolve_comment"])
    }

    @Test func requestingAReviewHandsBackItsId() async {
        let reply = await call(tools, "request_review", ["path": "docs/plans/rate-limiter.md", "note": "Check the rollout steps."])
        #expect(!reply.isError)
        #expect(reply.text.contains("Review 1"))
        #expect(reply.text.contains("wait_for_review"))
        #expect(await reviews.requested.first?.note == "Check the rollout steps.")
        let missing = await call(tools, "request_review", [:])
        #expect(missing.isError)
        let outside = await call(tools, "request_review", ["path": "notes/elsewhere.md"])
        #expect(outside.isError)
        #expect(outside.text.contains("watches"))
    }

    @Test func waitingReportsAReviewStillOpen() async {
        _ = await call(tools, "request_review", ["path": "docs/plans/rate-limiter.md"])
        let reply = await call(tools, "wait_for_review", ["id": 1, "seconds": 0])
        #expect(!reply.isError)
        #expect(reply.text.contains("still reviewing"))
    }

    @Test func waitingReturnsTheCommentsOnceTheReviewIsDone() async {
        _ = await call(tools, "request_review", ["path": "docs/plans/rate-limiter.md"])
        let comment = BridgeComment(id: 9, path: "/Users/me/code/api-gateway/docs/plans/rate-limiter.md", relativePath: "docs/plans/rate-limiter.md",
                                    lineStart: 14, lineEnd: 14, quote: "Shadow mode", body: "Log for a week first.")
        Task {
            try? await Task.sleep(for: .milliseconds(40))
            await reviews.finish(1, comments: [comment])
        }
        let reply = await call(tools, "wait_for_review", ["id": 1, "seconds": 5])
        #expect(reply.text.contains("Review 1 is done"))
        #expect(reply.text.contains("Comment 9"))
        #expect(reply.text.contains("Log for a week first."))
        await reviews.finish(1, comments: [])
        let approved = await call(tools, "wait_for_review", ["id": 1])
        #expect(approved.text.contains("no comments"))
    }

    @Test func waitingOnAnUnknownReviewIsAnError() async {
        let reply = await call(tools, "wait_for_review", ["id": 42])
        #expect(reply.isError)
    }
}
