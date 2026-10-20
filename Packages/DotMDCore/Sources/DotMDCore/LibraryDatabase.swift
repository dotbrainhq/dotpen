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

    /// Opens the database at url. A file that isn't a database, is corrupt, or fails migration is moved aside, kept
    /// for support, and replaced. Any other error, such as a locked or busy file, is rethrown and the file left alone.
    public static func open(at url: URL) throws -> LibraryDatabase {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            return try openOrMigrate(at: url)
        } catch let failure as OpenFailure {
            guard failure.isBroken else { throw failure.error }
            try moveAside(url)
            return try LibraryDatabase(DatabasePool(path: url.path))
        }
    }

    /// Why open(at:) failed, and whether the failure came from migrating rather than opening.
    private struct OpenFailure: Error {
        let error: any Error
        let duringMigration: Bool

        /// Not a database or corrupt, wherever it happened. During migration, anything except an SQLite error
        /// caused by the file's surroundings (locks, disk, permissions) rather than its contents.
        var isBroken: Bool {
            guard let error = error as? DatabaseError else { return duringMigration }
            switch error.resultCode {
            case .SQLITE_NOTADB, .SQLITE_CORRUPT:
                return true
            case .SQLITE_BUSY, .SQLITE_LOCKED, .SQLITE_IOERR, .SQLITE_CANTOPEN, .SQLITE_FULL, .SQLITE_NOMEM,
                 .SQLITE_READONLY, .SQLITE_PERM, .SQLITE_AUTH, .SQLITE_INTERRUPT:
                return false
            default:
                return duringMigration
            }
        }
    }

    private static func openOrMigrate(at url: URL) throws -> LibraryDatabase {
        let pool: DatabasePool
        do {
            pool = try DatabasePool(path: url.path)
        } catch {
            throw OpenFailure(error: error, duringMigration: false)
        }
        do {
            return try LibraryDatabase(pool)
        } catch {
            throw OpenFailure(error: error, duringMigration: true)
        }
    }

    /// Renames the database to library-broken-<stamp>-<id>.sqlite. The -wal and -shm files go first, and failing to
    /// move them doesn't stop the main file from moving.
    private static func moveAside(_ url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let id = UUID().uuidString.prefix(8).lowercased()
        let brokenName = "library-broken-\(stamp)-\(id).sqlite"
        for suffix in ["-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            try? FileManager.default.moveItem(at: file, to: directory.appending(path: brokenName + suffix))
        }
        try FileManager.default.moveItem(at: url, to: directory.appending(path: brokenName))
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
                t.column("indexedAt", .datetime)
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

    public func folder(id: Int64) throws -> WatchedFolder? {
        try writer.read { db in try WatchedFolder.fetchOne(db, key: id) }
    }

    /// Saves every field except indexedAt, which only replaceDocuments writes. A caller holding an older copy of
    /// the folder can't undo a finished first scan.
    public func update(_ folder: WatchedFolder) throws {
        try writer.write { db in try folder.update(db, columns: ["bookmark", "path", "name", "color", "addedAt"]) }
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

    /// Makes the stored documents match a full scan, and records the scan in the folder's indexedAt.
    /// - On the folder's first scan (indexedAt is nil) every file counts as read, so only what changes afterwards
    ///   shows as new. A scan that never gets here leaves indexedAt nil, so the next one still counts as first.
    /// - Rows at `unreadable` paths are kept as they are: the file exists but couldn't be read this time.
    /// - New rows at `readPaths` are inserted as read. Used for files that only show because ignored paths are shown.
    public func replaceDocuments(folderID: Int64, with files: [ScannedFile], unreadable: Set<String> = [],
                                 readPaths: Set<String> = []) throws {
        try writer.write { db in
            // Removed while the scan ran: its rows went with it.
            guard var folder = try WatchedFolder.fetchOne(db, key: folderID) else { return }
            let firstScan = folder.indexedAt == nil
            let stored = try Document.filter(Document.Fields.folderID == folderID).fetchAll(db)
            // Swift compares strings by canonical equivalence and SQLite by bytes, so NFC and NFD spellings of one
            // path can both be stored. Keep one row per path and drop the twins.
            var existing = Dictionary(stored.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
            let kept = Set(existing.values.map(\.key))
            for document in stored where !kept.contains(document.key) {
                _ = try document.delete(db)
            }
            for file in files {
                if var document = existing.removeValue(forKey: file.relativePath) {
                    guard document.differs(from: file) else { continue }
                    document.apply(file)
                    try document.update(db)
                } else {
                    let read = firstScan || readPaths.contains(file.relativePath)
                    var document = Document(folderID: folderID, file: file, readHash: read ? file.contentHash : nil)
                    try document.insert(db)
                }
            }
            for document in existing.values where !unreadable.contains(document.relativePath) {
                _ = try document.delete(db)
            }
            folder.indexedAt = .now
            try folder.update(db, columns: ["indexedAt"])
        }
    }

    /// Inserts or updates one file and returns the stored document. A new row counts as read when readIfNew is true.
    @discardableResult
    public func upsert(_ file: ScannedFile, folderID: Int64, readIfNew: Bool = false) throws -> Document {
        try writer.write { db in
            let match = Document.filter(Document.Fields.folderID == folderID && Document.Fields.relativePath == file.relativePath)
            if var document = try match.fetchOne(db) {
                if document.differs(from: file) {
                    document.apply(file)
                    try document.update(db)
                }
                return document
            }
            var document = Document(folderID: folderID, file: file, readHash: readIfNew ? file.contentHash : nil)
            try document.insert(db)
            return document
        }
    }

    public func deleteDocument(folderID: Int64, relativePath: String) throws {
        _ = try writer.write { db in
            try Document.filter(Document.Fields.folderID == folderID && Document.Fields.relativePath == relativePath).deleteAll(db)
        }
    }

    /// Returns the updated document, or nil when there is no document with that id.
    @discardableResult
    public func markRead(documentID: Int64, at date: Date = .now) throws -> Document? {
        try writer.write { db in
            guard var document = try Document.fetchOne(db, key: documentID) else { return nil }
            document.readHash = document.contentHash
            document.lastReadAt = date
            try document.update(db)
            return document
        }
    }

    /// Returns the updated document, or nil when there is no document with that id.
    @discardableResult
    public func markUnread(documentID: Int64) throws -> Document? {
        try writer.write { db in
            guard var document = try Document.fetchOne(db, key: documentID) else { return nil }
            document.readHash = nil
            try document.update(db)
            return document
        }
    }

    /// Returns the updated document, or nil when there is no document with that id.
    @discardableResult
    public func setPinned(documentID: Int64, _ pinned: Bool) throws -> Document? {
        try writer.write { db in
            guard var document = try Document.fetchOne(db, key: documentID) else { return nil }
            document.pinned = pinned
            try document.update(db)
            return document
        }
    }
}
