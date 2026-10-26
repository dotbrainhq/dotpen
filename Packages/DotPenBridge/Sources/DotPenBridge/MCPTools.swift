import Foundation

/// The bridge's MCP methods, apart from HTTP: initialize, ping, tools/list and tools/call for list_comments,
/// get_comments and resolve_comment, plus request_review and wait_for_review when the app offers reviews. Requests and
/// responses are JSON-RPC objects.
public struct MCPTools: Sendable {
    public static let serverName = "dotpen"
    public static let latestProtocol = "2025-06-18"
    static let instructions = """
    dotPen holds review comments a person wrote on Markdown files. Call get_comments with a file's path to read \
    the ones on that file, or list_comments for all of them. Each comment quotes the passage it is about and \
    gives its lines. Make the change it asks for, then call resolve_comment with its id.
    """
    static let reviewInstructions = """
     When you finish a Markdown file the person should check before you go on, call request_review with its path, \
    then call wait_for_review until it reports the review done, and work through the comments it returns.
    """
    /// The longest one wait_for_review call waits: agents put their own time limits on tool calls.
    static let longestWait = 50

    let source: any CommentSource
    let reviews: (any ReviewSource)?
    /// How often wait_for_review checks on the review.
    let reviewPollInterval: Duration
    let version: String
    /// dotPen's icon as PNG, sent inside the reply so the agent's app fetches nothing to show it.
    let icon: Data?
    /// Called with the agent's name, like "Claude Code", each time one connects.
    let connected: @Sendable (String) -> ()

    public init(source: any CommentSource, reviews: (any ReviewSource)? = nil, version: String, icon: Data? = nil,
                connected: @escaping @Sendable (String) -> () = { _ in }, reviewPollInterval: Duration = .seconds(1)) {
        self.source = source
        self.reviews = reviews
        self.reviewPollInterval = reviewPollInterval
        self.version = version
        self.icon = icon
        self.connected = connected
    }

    /// The name an agent's MCP client gives, as people know it: "claude-code" is Claude Code.
    public static func agentName(forClient client: String) -> String {
        let id = client.lowercased()
        if id.contains("claude") { return "Claude Code" }
        if id.contains("codex") { return "Codex" }
        if id.contains("cursor") { return "Cursor" }
        if id.contains("gemini") { return "Gemini CLI" }
        if id.contains("grok") { return "Grok CLI" }
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
                "serverInfo": serverInfo,
                "instructions": Self.instructions + (reviews == nil ? "" : Self.reviewInstructions),
            ])
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": Self.toolList + (reviews == nil ? [] : Self.reviewTools)])
        case "tools/call":
            return await call(id: id, params: params)
        default:
            return Self.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    /// The name, title, description and icon MCP's 2025-11-25 spec lets an agent's app show for the server.
    private var serverInfo: [String: Any] {
        var info: [String: Any] = [
            "name": Self.serverName,
            "title": "dotPen",
            "version": version,
            "description": "Review comments you wrote on Markdown files in dotPen, for your agent to read and resolve.",
        ]
        if let icon {
            info["icons"] = [["src": "data:image/png;base64," + icon.base64EncodedString(), "mimeType": "image/png", "sizes": ["128x128"]]]
        }
        return info
    }

    static var toolList: [[String: Any]] {
        [
            [
                "name": "list_comments",
                "description": "Every open review comment in dotPen's watched folders, with its file, lines, quoted passage and text.",
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

    static var reviewTools: [[String: Any]] {
        [
            [
                "name": "request_review",
                "description": "Asks the person to review a Markdown file in dotPen before you go on. dotPen shows the request; call wait_for_review with the id it returns.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string", "description": "The Markdown file's path, relative to the repository or absolute."],
                        "note": ["type": "string", "description": "Optional: what you'd like the person to look at."],
                    ],
                    "required": ["path"],
                ],
            ],
            [
                "name": "wait_for_review",
                "description": "Waits for a review you asked for, up to \(longestWait) seconds per call. Returns the person's comments once they mark it done; call again while they're still reviewing.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "integer", "description": "The id request_review returned."],
                        "seconds": ["type": "integer", "description": "How long to wait, up to \(longestWait). Default \(longestWait)."],
                    ],
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
        case "request_review" where reviews != nil:
            guard let path = arguments["path"] as? String, !path.isEmpty else {
                return Self.toolResult(id: id, "Pass the file's path.", isError: true)
            }
            let note = (arguments["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            guard let review = await reviews?.requestReview(path: path, note: note) else {
                return Self.toolResult(id: id, "\(path) isn't in a folder dotPen watches, so dotPen can't show it for review.", isError: true)
            }
            return Self.toolResult(id: id, "Review \(review) requested for \(path). dotPen is showing it to the person. Call wait_for_review with id \(review) to wait for their comments.")
        case "wait_for_review" where reviews != nil:
            guard let number = arguments["id"] as? NSNumber else {
                return Self.toolResult(id: id, "Pass the review's id.", isError: true)
            }
            let seconds = min(max((arguments["seconds"] as? NSNumber)?.intValue ?? Self.longestWait, 0), Self.longestWait)
            return await waitForReview(id: id, review: number.int64Value, seconds: seconds)
        case let name:
            return Self.error(id: id, code: -32602, message: "Unknown tool: \(name ?? "none")")
        }
    }

    private func waitForReview(id: Any, review: Int64, seconds: Int) async -> [String: Any] {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while true {
            switch await reviews?.reviewStatus(id: review) ?? .unknown {
            case .unknown:
                return Self.toolResult(id: id, "No review \(review). dotPen may have quit since it was requested; call request_review again.", isError: true)
            case let .done(comments) where comments.isEmpty:
                return Self.toolResult(id: id, "Review \(review) is done, with no comments: the person read it and has nothing to change.")
            case let .done(comments):
                let count = comments.count == 1 ? "1 comment" : "\(comments.count) comments"
                return Self.toolResult(id: id, "Review \(review) is done. The person left \(count):\n\n\(Self.describe(comments))\n\nMake each change, then call resolve_comment with its id.")
            case .pending:
                if ContinuousClock.now >= deadline {
                    return Self.toolResult(id: id, "The person is still reviewing. Call wait_for_review with id \(review) again.")
                }
                try? await Task.sleep(for: reviewPollInterval)
            }
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
