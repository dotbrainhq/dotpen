import AppKit
import DotMDBridge
import DotMDCore
import Observation

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
