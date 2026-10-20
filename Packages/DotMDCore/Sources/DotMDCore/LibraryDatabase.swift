import Foundation
import GRDB

/// The library in one SQLite file: watched folders and their Markdown documents.
public final class LibraryDatabase: Sendable {
    private let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func inMemory() throws -> LibraryDatabase {
        try LibraryDatabase(DatabaseQueue())
    }

    /// Opens the database at url. A file that can't be opened or migrated is moved aside, kept for support, and replaced.
    public static func open(at url: URL) throws -> LibraryDatabase {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            return try LibraryDatabase(DatabasePool(path: url.path))
        } catch {
            let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
            for suffix in ["", "-wal", "-shm"] {
                let file = URL(fileURLWithPath: url.path + suffix)
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                try FileManager.default.moveItem(at: file, to: directory.appending(path: "library-broken-\(stamp).sqlite\(suffix)"))
            }
            return try LibraryDatabase(DatabasePool(path: url.path))
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "folder") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bookmark", .blob).notNull()
                t.column("path", .text).notNull()
                t.column("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("addedAt", .datetime).notNull()
            }
            try db.create(table: "document") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("folder", onDelete: .cascade).notNull()
                t.column("relativePath", .text).notNull()
                t.column("title", .text)
                t.column("kind", .text).notNull()
                t.column("contentHash", .text).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("readHash", .text)
                t.column("lastReadAt", .datetime)
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.uniqueKey(["folderId", "relativePath"])
            }
        }
        return migrator
    }

    // MARK: Folders

    public func folders() throws -> [WatchedFolder] {
        try writer.read { db in try WatchedFolder.order(Column("addedAt")).fetchAll(db) }
    }

    public func insert(_ folder: WatchedFolder) throws -> WatchedFolder {
        try writer.write { db in
            var folder = folder
            try folder.insert(db)
            return folder
        }
    }

    public func update(_ folder: WatchedFolder) throws {
        try writer.write { db in try folder.update(db) }
    }

    public func deleteFolder(id: Int64) throws {
        _ = try writer.write { db in try WatchedFolder.deleteOne(db, key: id) }
    }

    // MARK: Documents

    public func documents(folderID: Int64) throws -> [Document] {
        try writer.read { db in try Document.filter(Document.Fields.folderID == folderID).fetchAll(db) }
    }

    public func document(folderID: Int64, relativePath: String) throws -> Document? {
        try writer.read { db in
            try Document.filter(Document.Fields.folderID == folderID && Document.Fields.relativePath == relativePath).fetchOne(db)
        }
    }

    /// Makes the stored documents match a full scan. On a folder's first scan every file counts as read,
    /// so only what changes afterwards shows as new.
    public func replaceDocuments(folderID: Int64, with files: [ScannedFile], firstScan: Bool) throws {
        try writer.write { db in
            let stored = try Document.filter(Document.Fields.folderID == folderID).fetchAll(db)
            var existing = Dictionary(uniqueKeysWithValues: stored.map { ($0.relativePath, $0) })
            for file in files {
                if var document = existing.removeValue(forKey: file.relativePath) {
                    guard document.differs(from: file) else { continue }
                    document.apply(file)
                    try document.update(db)
                } else {
                    var document = Document(folderID: folderID, file: file, readHash: firstScan ? file.contentHash : nil)
                    try document.insert(db)
                }
            }
            for document in existing.values {
                _ = try document.delete(db)
            }
        }
    }

    /// Inserts or updates one file and returns the stored document.
    @discardableResult
    public func upsert(_ file: ScannedFile, folderID: Int64) throws -> Document {
        try writer.write { db in
            let match = Document.filter(Document.Fields.folderID == folderID && Document.Fields.relativePath == file.relativePath)
            if var document = try match.fetchOne(db) {
                if document.differs(from: file) {
                    document.apply(file)
                    try document.update(db)
                }
                return document
            }
            var document = Document(folderID: folderID, file: file, readHash: nil)
            try document.insert(db)
            return document
        }
    }

    public func deleteDocument(folderID: Int64, relativePath: String) throws {
        _ = try writer.write { db in
            try Document.filter(Document.Fields.folderID == folderID && Document.Fields.relativePath == relativePath).deleteAll(db)
        }
    }

    public func markRead(documentID: Int64, at date: Date = .now) throws {
        try writer.write { db in
            guard var document = try Document.fetchOne(db, key: documentID) else { return }
            document.readHash = document.contentHash
            document.lastReadAt = date
            try document.update(db)
        }
    }

    public func markUnread(documentID: Int64) throws {
        try writer.write { db in
            guard var document = try Document.fetchOne(db, key: documentID) else { return }
            document.readHash = nil
            try document.update(db)
        }
    }

    public func setPinned(documentID: Int64, _ pinned: Bool) throws {
        try writer.write { db in
            guard var document = try Document.fetchOne(db, key: documentID) else { return }
            document.pinned = pinned
            try document.update(db)
        }
    }
}
