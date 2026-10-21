import Foundation

/// A comment as an agent sees it through the bridge.
public struct BridgeComment: Codable, Equatable, Sendable {
    public var id: Int64
    /// The file's full path on disk.
    public var path: String
    /// The file's path in its watched folder, which is usually the repository the agent works in.
    public var relativePath: String
    public var lineStart: Int
    public var lineEnd: Int
    public var quote: String
    public var body: String

    public init(id: Int64, path: String, relativePath: String, lineStart: Int, lineEnd: Int, quote: String, body: String) {
        self.id = id
        self.path = path
        self.relativePath = relativePath
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.quote = quote
        self.body = body
    }
}

/// Where the bridge reads open comments and resolves them. The app backs it with the library.
public protocol CommentSource: Sendable {
    /// Every open comment in the watched folders.
    func openComments() async -> [BridgeComment]
    /// Marks a comment resolved. False when there is no open comment with that id.
    func resolve(id: Int64) async -> Bool
}
