import Foundation

/// The bridge's MCP methods, apart from HTTP: initialize, ping, tools/list and tools/call for list_comments,
/// get_comments and resolve_comment. Requests and responses are JSON-RPC objects.
public struct MCPTools: Sendable {
    public static let serverName = "dotmd"
    public static let latestProtocol = "2025-06-18"
    static let instructions = """
    DotMD holds review comments a person wrote on Markdown files. Call get_comments with a file's path to read \
    the ones on that file, or list_comments for all of them. Each comment quotes the passage it is about and \
    gives its lines. Make the change it asks for, then call resolve_comment with its id.
    """

    let source: any CommentSource
    let version: String
    /// Called with the agent's name, like "Claude Code", each time one connects.
    let connected: @Sendable (String) -> ()

    public init(source: any CommentSource, version: String, connected: @escaping @Sendable (String) -> () = { _ in }) {
        self.source = source
        self.version = version
        self.connected = connected
    }

    /// The name an agent's MCP client gives, as people know it: "claude-code" is Claude Code.
    public static func agentName(forClient client: String) -> String {
        let id = client.lowercased()
        if id.contains("claude") { return "Claude Code" }
        if id.contains("codex") { return "Codex" }
        if id.contains("cursor") { return "Cursor" }
        return client
    }

    /// The response to a request, or nil for a notification, which gets none.
    public func respond(to request: [String: Any]) async -> [String: Any]? {
        guard let method = request["method"] as? String else {
            return Self.error(id: request["id"], code: -32600, message: "Invalid request")
        }
        guard let id = request["id"] else { return nil }
        let params = request["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            if let client = (params["clientInfo"] as? [String: Any])?["name"] as? String, !client.isEmpty {
                connected(Self.agentName(forClient: client))
            }
            return Self.result(id: id, [
                "protocolVersion": params["protocolVersion"] as? String ?? Self.latestProtocol,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": Self.serverName, "version": version],
                "instructions": Self.instructions,
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": Self.toolList])
        case "tools/call":
            return await call(id: id, params: params)
        default:
            return Self.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    static var toolList: [[String: Any]] {
        [
            [
                "name": "list_comments",
                "description": "Every open review comment in DotMD's watched folders, with its file, lines, quoted passage and text.",
                "inputSchema": ["type": "object", "properties": [String: Any]()],
            ],
            [
                "name": "get_comments",
                "description": "The open review comments on one Markdown file. Pass its path, relative to the repository or absolute.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["path": ["type": "string", "description": "The Markdown file's path."]],
                    "required": ["path"],
                ],
            ],
            [
                "name": "resolve_comment",
                "description": "Marks a review comment resolved once its change is made.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["id": ["type": "integer", "description": "The comment's id."]],
                    "required": ["id"],
                ],
            ],
        ]
    }

    private func call(id: Any, params: [String: Any]) async -> [String: Any] {
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        switch params["name"] as? String {
        case "list_comments":
            return Self.toolResult(id: id, Self.describe(await source.openComments()))
        case "get_comments":
            guard let path = arguments["path"] as? String, !path.isEmpty else {
                return Self.toolResult(id: id, "Pass the file's path.", isError: true)
            }
            return Self.toolResult(id: id, Self.describe(Self.matching(path, in: await source.openComments())))
        case "resolve_comment":
            guard let number = arguments["id"] as? NSNumber else {
                return Self.toolResult(id: id, "Pass the comment's id.", isError: true)
            }
            let resolved = await source.resolve(id: number.int64Value)
            return Self.toolResult(id: id, resolved ? "Resolved comment \(number)." : "No open comment \(number).", isError: !resolved)
        case let name:
            return Self.error(id: id, code: -32602, message: "Unknown tool: \(name ?? "none")")
        }
    }

    /// Comments on the file at path: its full path, its path in the watched folder, or a path that ends either.
    static func matching(_ path: String, in comments: [BridgeComment]) -> [BridgeComment] {
        let wanted = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        return comments.filter { comment in
            comment.path == wanted || comment.relativePath == wanted
                || comment.path.hasSuffix("/" + wanted) || wanted.hasSuffix("/" + comment.relativePath)
        }
    }

    /// Plain text an agent reads well: one entry per comment.
    static func describe(_ comments: [BridgeComment]) -> String {
        guard !comments.isEmpty else { return "No open comments." }
        return comments.map { comment in
            let lines = comment.lineStart == comment.lineEnd ? "line \(comment.lineStart)" : "lines \(comment.lineStart)-\(comment.lineEnd)"
            return """
            Comment \(comment.id) on \(comment.relativePath), \(lines)
            Passage: "\(comment.quote)"
            Comment: \(comment.body)
            File: \(comment.path)
            """
        }.joined(separator: "\n\n")
    }

    private static func toolResult(id: Any, _ text: String, isError: Bool = false) -> [String: Any] {
        result(id: id, ["content": [["type": "text", "text": text]], "isError": isError])
    }

    private static func result(id: Any, _ value: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": value]
    }

    static func error(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }
}
