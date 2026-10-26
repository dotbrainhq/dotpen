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
        let reviews = LibraryReviewSource(queue: AppServices.reviews) { AppServices.bridge.lastAgent }
        let tools = MCPTools(source: LibraryCommentSource(library: library), reviews: reviews, version: Self.version, icon: Self.icon) { [weak self] name in
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
            library.openComments().map { Self.bridgeComment($0, in: $1, library: library) }
        }
    }

    @MainActor
    static func bridgeComment(_ comment: Comment, in document: DotMDCore.Document, library: Library) -> BridgeComment {
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

    func resolve(id: Int64) async -> Bool {
        await MainActor.run {
            guard let comment = library.openComments().first(where: { $0.0.key == id })?.0 else { return false }
            library.setResolved(comment, true)
            return true
        }
    }
}

/// Reviews agents ask for over the bridge: which files wait on the person, and the comments they leave when they're
/// done. Kept in memory: an agent whose DotMD quit hears there's no such review and asks again.
@MainActor
@Observable
final class ReviewQueue {
    struct Review: Equatable {
        let id: Int64
        let documentKey: Int64
        /// The agent that asked, like "Claude Code", when it said who it was.
        let agent: String?
        let note: String?
        /// The open comments on the file when the person pressed Done Reviewing. Nil while it waits on them.
        var comments: [BridgeComment]?
    }

    private(set) var reviews: [Int64: Review] = [:]
    @ObservationIgnored private var nextID: Int64 = 1
    private let library: Library

    init(library: Library) {
        self.library = library
    }

    /// The oldest review still waiting on this file.
    func pending(for documentKey: Int64) -> Review? {
        reviews.values.filter { $0.documentKey == documentKey && $0.comments == nil }.min { $0.id < $1.id }
    }

    /// Files waiting on the person, for the Dock badge.
    var waitingFiles: Int {
        Set(reviews.values.filter { $0.comments == nil }.map(\.documentKey)).count
    }

    /// An agent's request. Nil when the path isn't a file in a watched folder.
    func request(path: String, note: String?, agent: String?) -> Int64? {
        guard let document = document(matching: path) else { return nil }
        let id = nextID
        nextID += 1
        reviews[id] = Review(id: id, documentKey: document.key, agent: agent, note: note, comments: nil)
        updateDockBadge()
        return id
    }

    func status(of id: Int64) -> ReviewStatus {
        guard let review = reviews[id] else { return .unknown }
        return review.comments.map { .done($0) } ?? .pending
    }

    /// Done Reviewing: every review waiting on this file is answered with the comments open on it now.
    func finish(documentKey: Int64) {
        let comments = library.openComments()
            .filter { $0.1.key == documentKey }
            .map { LibraryCommentSource.bridgeComment($0.0, in: $0.1, library: library) }
        for (id, review) in reviews where review.documentKey == documentKey && review.comments == nil {
            reviews[id]?.comments = comments
        }
        updateDockBadge()
    }

    /// The path an agent passes: absolute, or relative to its repository, which is usually the watched folder.
    private func document(matching path: String) -> DotMDCore.Document? {
        let wanted = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        if wanted.hasPrefix("/") { return library.document(at: URL(fileURLWithPath: wanted)) }
        let all = library.folders.flatMap(\.documents)
        return all.first { $0.relativePath == wanted }
            ?? all.first { wanted.hasSuffix("/" + $0.relativePath) || $0.relativePath.hasSuffix("/" + wanted) }
    }

    private func updateDockBadge() {
        let count = waitingFiles
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }
}

/// The queue as the bridge sees it.
struct LibraryReviewSource: ReviewSource {
    let queue: ReviewQueue
    let agent: @MainActor () -> String?

    func requestReview(path: String, note: String?) async -> Int64? {
        await MainActor.run { queue.request(path: path, note: note, agent: agent()) }
    }

    func reviewStatus(id: Int64) async -> ReviewStatus {
        await MainActor.run { queue.status(of: id) }
    }
}
