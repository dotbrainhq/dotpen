import DotMDBridge
import DotMDCore
import Foundation
import Observation

/// Who is writing what, read from the agents' session logs once the person allows each log folder in Settings.
/// Without access, dotPen still works: files show as written, just without an agent's name.
@MainActor
@Observable
final class AgentActivity {
    /// The latest write to each file, by full path.
    private(set) var writes: [String: AgentWrite] = [:]
    /// Every session the logs mention, by agent and id, with when its log last moved.
    private(set) var sessions: [String: AgentSession] = [:]
    /// The latest write to a Markdown file in a watched folder, for the arrival banner. Cleared when dismissed.
    private(set) var arrival: AgentWrite?
    /// Log folders the person allowed.
    private(set) var granted: Set<Agent> = []
    /// Moves every few seconds, so sessions that went quiet stop counting as writing.
    private(set) var now = Date.now

    /// A session counts as active while its log moved in the last 90 seconds, and as writing a file while it wrote
    /// that file in the last two minutes.
    static let activeWindow: TimeInterval = 90
    static let writingWindow: TimeInterval = 120

    private let library: Library
    private var watched: [Agent: Watched] = [:]
    private var ticker: Task<(), Never>?

    private struct Watched {
        let url: URL
        let folder: SessionLogFolder
        let watcher: FolderWatcher
        let queue: DispatchQueue
    }

    init(library: Library) {
        self.library = library
    }

    /// Where each agent keeps its logs, in the person's real home folder.
    static func logFolder(for agent: Agent) -> URL {
        let home = URL(fileURLWithPath: RealHome.account, isDirectory: true)
        switch agent {
        case .claudeCode: return home.appending(path: ".claude/projects", directoryHint: .isDirectory)
        case .codex: return home.appending(path: ".codex/sessions", directoryHint: .isDirectory)
        }
    }

    /// Opens the log folders the person allowed before. Every window calls this; only the first call does anything.
    func start() {
        guard ticker == nil else { return }
        for agent in Agent.allCases {
            guard let bookmark = UserDefaults.standard.data(forKey: Self.key(agent)),
                  let resolved = try? FolderAccess.resolve(bookmark) else { continue }
            if let fresh = resolved.refreshedBookmark { UserDefaults.standard.set(fresh, forKey: Self.key(agent)) }
            watch(agent, at: resolved.url)
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.now = .now
            }
        }
    }

    /// How Settings names the log folder.
    static func logFolderName(for agent: Agent) -> String {
        switch agent {
        case .claudeCode: "~/.claude/projects"
        case .codex: "~/.codex/sessions"
        }
    }

    /// Asks for an agent's log folder in an open panel, starting where the agent keeps it.
    func grantAccess(to agent: Agent) {
        guard let url = FolderPicker.chooseFolder(
            message: "Choose \(Self.logFolderName(for: agent)) so dotPen can see which files \(agent.name) writes. dotPen only reads it, on this Mac.",
            prompt: "Allow",
            startingAt: Self.logFolder(for: agent),
            showsHidden: true
        ), let bookmark = try? FolderAccess.bookmark(for: url) else { return }
        UserDefaults.standard.set(bookmark, forKey: Self.key(agent))
        stopWatching(agent)
        if let resolved = try? FolderAccess.resolve(bookmark) { watch(agent, at: resolved.url) }
    }

    func revokeAccess(to agent: Agent) {
        UserDefaults.standard.removeObject(forKey: Self.key(agent))
        stopWatching(agent)
        writes = writes.filter { $0.value.agent != agent }
        sessions = sessions.filter { $0.value.agent != agent }
        if arrival?.agent == agent { arrival = nil }
    }

    // MARK: Questions views ask

    /// The agent that last wrote a file, if its log says so.
    func writer(for url: URL) -> AgentWrite? {
        writes[Self.path(url)]
    }

    /// The session writing a file right now: it wrote the file in the last two minutes and its log is still moving.
    func writingSession(for url: URL) -> AgentSession? {
        guard let write = writer(for: url), now.timeIntervalSince(write.at) <= Self.writingWindow,
              let session = sessions[Self.key(write.agent, write.sessionID)],
              now.timeIntervalSince(session.lastActivity) <= Self.activeWindow else { return nil }
        return session
    }

    /// The newest active session running inside a folder, for "Connected to Claude Code in api-gateway".
    func activeSession(in folder: URL, agent: String? = nil) -> AgentSession? {
        let root = Self.path(folder)
        return sessions.values
            .filter { now.timeIntervalSince($0.lastActivity) <= Self.activeWindow }
            .filter { $0.cwd == root || $0.cwd.hasPrefix(root + "/") || root.hasPrefix($0.cwd + "/") }
            .filter { agent == nil || $0.agent.name == agent }
            .max { $0.lastActivity < $1.lastActivity }
    }

    /// Sessions writing in a watched folder right now, newest first, for the menu bar item. Sessions working
    /// elsewhere on the Mac are none of dotPen's business and never show.
    var writingSessions: [(session: AgentSession, write: AgentWrite)] {
        sessions.values.compactMap { session -> (AgentSession, AgentWrite)? in
            guard now.timeIntervalSince(session.lastActivity) <= Self.activeWindow,
                  let write = writes.values
                    .filter({ $0.agent == session.agent && $0.sessionID == session.sessionID })
                    .filter({ library.folder(containing: URL(fileURLWithPath: $0.path)) != nil })
                    .max(by: { $0.at < $1.at }),
                  now.timeIntervalSince(write.at) <= Self.writingWindow else { return nil }
            return (session, write)
        }
        .sorted { $0.1.at > $1.1.at }
    }

    func dismissArrival() {
        arrival = nil
    }

    // MARK: Watching

    private func watch(_ agent: Agent, at url: URL) {
        let folder = SessionLogFolder(root: url, agent: agent)
        let queue = DispatchQueue(label: "app.dotpen.logs.\(agent.rawValue)")
        // Log lines arrive many times a second while an agent works; half a second keeps that to a few scans.
        let watcher = FolderWatcher(url: url, latency: 0.5) { [weak self] _ in
            queue.async {
                let writes = folder.scan()
                let sessions = folder.activeSessions(within: .infinity)
                Task { @MainActor in self?.apply(writes, sessions) }
            }
        }
        watched[agent] = Watched(url: url, folder: folder, watcher: watcher, queue: queue)
        granted.insert(agent)
        // Today's logs are read in full once, off the main thread.
        queue.async { [weak self] in
            let writes = folder.scan()
            let sessions = folder.activeSessions(within: .infinity)
            Task { @MainActor in self?.apply(writes, sessions, initial: true) }
        }
    }

    private func stopWatching(_ agent: Agent) {
        guard let watched = watched.removeValue(forKey: agent) else { return }
        watched.watcher.cancel()
        FolderAccess.stop(watched.url)
        granted.remove(agent)
    }

    private func apply(_ newWrites: [AgentWrite], _ newSessions: [AgentSession], initial: Bool = false) {
        now = .now
        for session in newSessions {
            sessions[Self.key(session.agent, session.sessionID)] = session
        }
        for write in newWrites {
            writes[write.path] = write
            // The banner is for something that just arrived, never for a replay of today's log.
            guard !initial, write.path.lowercased().hasSuffix(".md"), now.timeIntervalSince(write.at) <= 600 else { continue }
            let url = URL(fileURLWithPath: write.path)
            guard library.folder(containing: url) != nil else { continue }
            if library.document(at: url).map({ $0.readState == .new }) ?? true { arrival = write }
        }
    }

    private static func key(_ agent: Agent) -> String { "agentLogs.\(agent.rawValue)" }
    private static func key(_ agent: Agent, _ session: String) -> String { "\(agent.rawValue)/\(session)" }

    /// Log paths are real paths; document URLs come from resolved bookmarks. Both compare as standardized paths.
    static func path(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
