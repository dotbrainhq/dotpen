import Foundation
import GRDB
import Testing
@testable import DotMDCore

private func file(_ path: String, hash: String, title: String? = nil) -> ScannedFile {
    ScannedFile(relativePath: path, title: title, kind: .other, contentHash: hash, modifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
}

private func makeFolder(in database: LibraryDatabase) throws -> Int64 {
    try #require(database.insert(WatchedFolder(bookmark: Data([1]), path: "/tmp/repo", name: "repo", color: .blue)).id)
}

@Test func storesFolders() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    let folders = try database.folders()
    #expect(folders.map(\.id) == [id])
    #expect(folders.first?.color == .blue)
}

@Test func firstScanCountsEverythingAsRead() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    try database.replaceDocuments(folderID: id, with: [file("README.md", hash: "1"), file("docs/plan.md", hash: "2")])
    let documents = try database.documents(folderID: id)
    #expect(documents.count == 2)
    #expect(documents.allSatisfy { $0.readState == .read })
}

@Test func laterScansShowNewAndChangedFiles() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    try database.replaceDocuments(folderID: id, with: [file("README.md", hash: "1")])
    try database.replaceDocuments(folderID: id, with: [file("README.md", hash: "2"), file("HANDOFF.md", hash: "3")])
    #expect(try database.document(folderID: id, relativePath: "README.md")?.readState == .changed)
    #expect(try database.document(folderID: id, relativePath: "HANDOFF.md")?.readState == .new)
}

@Test func scansRemoveFilesThatAreGone() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    try database.replaceDocuments(folderID: id, with: [file("a.md", hash: "1"), file("b.md", hash: "2")])
    try database.replaceDocuments(folderID: id, with: [file("a.md", hash: "1")])
    #expect(try database.documents(folderID: id).map(\.relativePath) == ["a.md"])
}

@Test func upsertAddsNewFilesAndUpdatesTitles() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    let added = try database.upsert(file("notes.md", hash: "1", title: "Notes"), folderID: id)
    #expect(added.readState == .new)
    let renamed = try database.upsert(file("notes.md", hash: "1", title: "Better notes"), folderID: id)
    #expect(renamed.id == added.id)
    #expect(renamed.title == "Better notes")
}

@Test func readAndUnread() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    let document = try database.upsert(file("notes.md", hash: "1"), folderID: id)
    try database.markRead(documentID: document.key)
    let read = try #require(try database.document(folderID: id, relativePath: "notes.md"))
    #expect(read.readState == .read)
    #expect(read.lastReadAt != nil)
    try database.markUnread(documentID: document.key)
    #expect(try database.document(folderID: id, relativePath: "notes.md")?.readState == .new)
}

@Test func pinning() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    let document = try database.upsert(file("notes.md", hash: "1"), folderID: id)
    try database.setPinned(documentID: document.key, true)
    #expect(try database.document(folderID: id, relativePath: "notes.md")?.pinned == true)
}

@Test func deletingAFolderDeletesItsDocuments() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    try database.upsert(file("notes.md", hash: "1"), folderID: id)
    try database.deleteFolder(id: id)
    #expect(try database.folders().isEmpty)
    #expect(try database.documents(folderID: id).isEmpty)
}

@Test func aBrokenDatabaseFileIsMovedAside() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "dotmd-db-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "library.sqlite")
    try Data("not a database".utf8).write(to: url)
    let database = try LibraryDatabase.open(at: url)
    #expect(try database.folders().isEmpty)
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(names.contains { $0.hasPrefix("library-broken-") && $0.hasSuffix(".sqlite") })
}

@Test func aLockedDatabaseIsNotMovedAside() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "dotmd-db-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: "library.sqlite")
    // A healthy database in rollback-journal mode, held by another connection's exclusive transaction:
    // switching it to WAL fails with SQLITE_BUSY.
    let holder = try DatabaseQueue(path: url.path)
    try holder.write { db in try db.execute(sql: "CREATE TABLE note(text)") }
    try holder.inDatabase { db in
        try db.execute(sql: "BEGIN EXCLUSIVE; INSERT INTO note VALUES ('kept')")
        defer { try? db.execute(sql: "ROLLBACK") }
        #expect(throws: DatabaseError.self) { try LibraryDatabase.open(at: url) }
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(!names.contains { $0.hasPrefix("library-broken-") })
    #expect(try holder.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM note") } == 0)
    // Once the lock is gone the same file opens and migrates.
    #expect(try LibraryDatabase.open(at: url).folders().isEmpty)
}

@Test func theFirstScanIsRecordedOnTheFolder() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    #expect(try database.folder(id: id)?.indexedAt == nil)
    try database.replaceDocuments(folderID: id, with: [file("README.md", hash: "1")])
    #expect(try database.folder(id: id)?.indexedAt != nil)
    try database.replaceDocuments(folderID: id, with: [file("README.md", hash: "1"), file("HANDOFF.md", hash: "2")])
    #expect(try database.document(folderID: id, relativePath: "HANDOFF.md")?.readState == .new)
}

@Test func anInterruptedFirstScanLeavesTheNextOneFirst() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    // The first scan never wrote its rows, but an event did. The next full scan is still the first.
    try database.upsert(file("HANDOFF.md", hash: "1"), folderID: id)
    try database.replaceDocuments(folderID: id, with: [file("HANDOFF.md", hash: "1"), file("README.md", hash: "2")])
    #expect(try database.document(folderID: id, relativePath: "README.md")?.readState == .read)
    #expect(try database.document(folderID: id, relativePath: "HANDOFF.md")?.readState == .new)
}

@Test func savingAnOlderFolderCopyKeepsIndexedAt() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    var stale = try #require(try database.folder(id: id))
    try database.replaceDocuments(folderID: id, with: [file("README.md", hash: "1")])
    stale.color = .orange
    try database.update(stale)
    let saved = try #require(try database.folder(id: id))
    #expect(saved.color == .orange)
    #expect(saved.indexedAt != nil)
}

@Test func unreadablePathsKeepTheirRows() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    try database.replaceDocuments(folderID: id, with: [file("a.md", hash: "1"), file("b.md", hash: "2")])
    try database.replaceDocuments(folderID: id, with: [file("a.md", hash: "1")], unreadable: ["b.md"])
    #expect(try database.documents(folderID: id).map(\.relativePath).sorted() == ["a.md", "b.md"])
}

@Test func readPathsArriveRead() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    try database.replaceDocuments(folderID: id, with: [file("README.md", hash: "1")])
    try database.replaceDocuments(folderID: id, with: [file("README.md", hash: "1"), file("node_modules/a.md", hash: "2"),
                                                       file("new.md", hash: "3")], readPaths: ["node_modules/a.md"])
    #expect(try database.document(folderID: id, relativePath: "node_modules/a.md")?.readState == .read)
    #expect(try database.document(folderID: id, relativePath: "new.md")?.readState == .new)
}

@Test func pathsThatDifferOnlyInUnicodeFormDoNotCrashARescan() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    try database.upsert(file("caf\u{E9}.md", hash: "1"), folderID: id)
    try database.upsert(file("cafe\u{301}.md", hash: "1"), folderID: id)
    #expect(try database.documents(folderID: id).count == 2)
    try database.replaceDocuments(folderID: id, with: [file("caf\u{E9}.md", hash: "1")])
    #expect(try database.documents(folderID: id).count == 1)
}

@Test func markingReturnsTheUpdatedDocument() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    let document = try database.upsert(file("notes.md", hash: "1"), folderID: id)
    #expect(try database.markRead(documentID: document.key)?.readState == .read)
    #expect(try database.markUnread(documentID: document.key)?.readState == .new)
    #expect(try database.setPinned(documentID: document.key, true)?.pinned == true)
    #expect(try database.markRead(documentID: 999) == nil)
}

@Test func folderColorsSkipColorsInUse() {
    #expect(FolderColor.next(after: []) == .blue)
    #expect(FolderColor.next(after: [.blue, .indigo]) == .purple)
    #expect(!FolderColor.allCases.map(\.rawValue).contains("green"))
}
