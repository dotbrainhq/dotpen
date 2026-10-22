import AppKit
import DotMDBridge
import DotMDCore
import Foundation
import Observation

/// The agent bridge's switch and state, shared by every window. Settings turns it on and off; the Send sheet says
/// which agent last connected.
@MainActor
@Observable
final class AgentBridge {
    enum State: Equatable {
        case off
        case starting
        case running(port: UInt16)
        case failed(String)
    }

    private(set) var state = State.off
    private(set) var isEnabled: Bool
    /// The agent that last connected, like "Claude Code". Kept across launches.
    private(set) var lastAgent: String?

    private let library: Library
    private var server: BridgeServer?
    private static let enabledKey = "agentBridgeEnabled"
    private static let lastAgentKey = "agentBridgeLastAgent"

    init(library: Library) {
        self.library = library
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        lastAgent = UserDefaults.standard.string(forKey: Self.lastAgentKey)
    }

    var address: String { "http://127.0.0.1:\(BridgeServer.defaultPort)/mcp" }

    /// How each agent adds the bridge: a command the person runs once in Terminal, or a config entry to paste.
    struct Connection: Identifiable {
        let agent: String
        let detail: String
        let button: String
        let text: String

        var id: String { agent }
    }

    /// From each agent's own MCP docs. Gemini CLI writes to the project unless told otherwise, so it gets
    /// `--scope user` like Claude Code; Codex and Grok CLI write to the person's config by default.
    var connections: [Connection] {
        [
            Connection(agent: "Claude Code", detail: "Adds DotMD for every project. Run the copied command in Terminal.",
                       button: "Copy Command", text: "claude mcp add --transport http --scope user dotmd \(address)"),
            Connection(agent: "Codex", detail: "Adds DotMD to ~/.codex/config.toml. Run the copied command in Terminal.",
                       button: "Copy Command", text: "codex mcp add dotmd --url \(address)"),
            Connection(agent: "Gemini CLI", detail: "Adds DotMD for every project. Run the copied command in Terminal.",
                       button: "Copy Command", text: "gemini mcp add --scope user --transport http dotmd \(address)"),
            Connection(agent: "Grok CLI", detail: "Adds DotMD to Grok CLI. Run the copied command in Terminal.",
                       button: "Copy Command", text: "grok mcp add --transport http dotmd \(address)"),
            Connection(agent: "Cursor", detail: "Add the copied entry to ~/.cursor/mcp.json.",
                       button: "Copy JSON", text: "{\n  \"mcpServers\": {\n    \"dotmd\": { \"url\": \"\(address)\" }\n  }\n}"),
            Connection(agent: "Other agents", detail: "Any agent that speaks MCP over HTTP connects to \(address).",
                       button: "Copy Address", text: address),
        ]
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled { start() } else { stop() }
    }

    /// Starts the server when the bridge is on. Every window calls this as it opens; only the first one starts it.
    func startIfEnabled() {
        if isEnabled { start() }
    }

    func start() {
        guard server == nil else { return }
        let tools = MCPTools(source: LibraryCommentSource(library: library), version: Self.version, icon: Self.icon) { [weak self] name in
            Task { @MainActor in self?.connected(name) }
        }
        let server = BridgeServer(tools: tools)
        self.server = server
        state = .starting
        Task {
            do {
                let port = try await server.start(port: BridgeServer.defaultPort)
                guard self.server === server else { return }
                state = .running(port: port)
            } catch {
                guard self.server === server else { return }
                self.server = nil
                state = .failed("DotMD couldn't listen on port \(BridgeServer.defaultPort). Another app may be using it.")
            }
        }
    }

    func stop() {
        server?.stop()
        server = nil
        state = .off
    }

    private func connected(_ name: String) {
        lastAgent = name
        UserDefaults.standard.set(name, forKey: Self.lastAgentKey)
    }

    /// The 128 point brand icon, as the bridge's MCP icon.
    private static var icon: Data? {
        guard let image = NSImage(named: "BrandIconSmall"), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

/// The library's open comments, as the bridge hands them to agents.
struct LibraryCommentSource: CommentSource {
    let library: Library

    func openComments() async -> [BridgeComment] {
        await MainActor.run {
            library.openComments().map { comment, document in
                BridgeComment(
                    id: comment.key,
                    path: library.url(for: document)?.path ?? document.relativePath,
                    relativePath: document.relativePath,
                    lineStart: comment.lineStart,
                    lineEnd: comment.lineEnd,
                    quote: comment.quote,
                    body: comment.body
                )
            }
        }
    }

    func resolve(id: Int64) async -> Bool {
        await MainActor.run {
            guard let comment = library.openComments().first(where: { $0.0.key == id })?.0 else { return false }
            library.setResolved(comment, true)
            return true
        }
    }
}
