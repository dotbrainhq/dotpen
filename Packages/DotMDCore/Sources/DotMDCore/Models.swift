import Foundation
import GRDB

/// A folder the person chose to watch, kept with a security-scoped bookmark.
public struct WatchedFolder: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "folder"

    public var id: Int64?
    public var bookmark: Data
    /// The folder's canonical path when DotMD last opened it, for display and for matching file events.
    public var path: String
    public var name: String
    public var color: FolderColor
    public var addedAt: Date

    public init(id: Int64? = nil, bookmark: Data, path: String, name: String, color: FolderColor, addedAt: Date = .now) {
        self.id = id
        self.bookmark = bookmark
        self.path = path
        self.name = name
        self.color = color
        self.addedAt = addedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Folder colors the person can choose. Green is left out because green means "new to you".
public enum FolderColor: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case blue, indigo, purple, pink, red, orange, yellow, gray

    /// The first color not in use, so new folders look different without the person picking.
    public static func next(after used: [FolderColor]) -> FolderColor {
        allCases.first { !used.contains($0) } ?? allCases[used.count % allCases.count]
    }
}

public enum DocumentKind: String, Codable, CaseIterable, Sendable, DatabaseValueConvertible {
    case readme, plan, spec, changelog, agentInstructions, other

    /// SF Symbol for the file list.
    public var symbolName: String {
        switch self {
        case .readme: "book"
        case .plan: "list.bullet.clipboard"
        case .spec: "doc.text.magnifyingglass"
        case .changelog: "clock.arrow.circlepath"
        case .agentInstructions: "gearshape"
        case .other: "doc.text"
        }
    }
}

public enum ReadState: Sendable {
    case read, new, changed
}

/// What the scanner learns about one file. The database turns it into a Document.
public struct ScannedFile: Equatable, Sendable {
    public var relativePath: String
    public var title: String?
    public var kind: DocumentKind
    public var contentHash: String
    public var modifiedAt: Date

    public init(relativePath: String, title: String?, kind: DocumentKind, contentHash: String, modifiedAt: Date) {
        self.relativePath = relativePath
        self.title = title
        self.kind = kind
        self.contentHash = contentHash
        self.modifiedAt = modifiedAt
    }
}

/// One Markdown file inside a watched folder.
public struct Document: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "document"

    public var id: Int64?
    public var folderID: Int64
    public var relativePath: String
    public var title: String?
    public var kind: DocumentKind
    public var contentHash: String
    public var modifiedAt: Date
    /// The content hash when the person last read the file. Nil for a file they haven't opened since it appeared.
    public var readHash: String?
    public var lastReadAt: Date?
    public var pinned: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case folderID = "folderId"
        case relativePath, title, kind, contentHash, modifiedAt, readHash, lastReadAt, pinned
    }

    enum Fields {
        static let folderID = Column(CodingKeys.folderID)
        static let relativePath = Column(CodingKeys.relativePath)
    }

    public init(folderID: Int64, file: ScannedFile, readHash: String?) {
        id = nil
        self.folderID = folderID
        relativePath = file.relativePath
        title = file.title
        kind = file.kind
        contentHash = file.contentHash
        modifiedAt = file.modifiedAt
        self.readHash = readHash
        lastReadAt = nil
        pinned = false
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    mutating func apply(_ file: ScannedFile) {
        title = file.title
        kind = file.kind
        contentHash = file.contentHash
        modifiedAt = file.modifiedAt
    }

    func differs(from file: ScannedFile) -> Bool {
        contentHash != file.contentHash || title != file.title || kind != file.kind
    }

    public var readState: ReadState {
        guard let readHash else { return .new }
        return readHash == contentHash ? .read : .changed
    }

    /// Selection key for SwiftUI. Stored documents always have an id.
    public var key: Int64 { id ?? 0 }
    public var fileName: String { (relativePath as NSString).lastPathComponent }
    /// The folder part of the relative path, or "" for files at the root.
    public var directory: String { (relativePath as NSString).deletingLastPathComponent }

    public func displayName(showTitles: Bool) -> String {
        showTitles ? (title ?? fileName) : fileName
    }
}
