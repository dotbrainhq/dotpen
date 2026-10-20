import Foundation
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
    try database.replaceDocuments(folderID: id, with: [file("README.md", hash: "1"), file("docs/plan.md", hash: "2")], firstScan: true)
    let documents = try database.documents(folderID: id)
    #expect(documents.count == 2)
    #expect(documents.allSatisfy { $0.readState == .read })
}

@Test func laterScansShowNewAndChangedFiles() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    try database.replaceDocuments(folderID: id, with: [file("README.md", hash: "1")], firstScan: true)
    try database.replaceDocuments(folderID: id, with: [file("README.md", hash: "2"), file("HANDOFF.md", hash: "3")], firstScan: false)
    #expect(try database.document(folderID: id, relativePath: "README.md")?.readState == .changed)
    #expect(try database.document(folderID: id, relativePath: "HANDOFF.md")?.readState == .new)
}

@Test func scansRemoveFilesThatAreGone() throws {
    let database = try LibraryDatabase.inMemory()
    let id = try makeFolder(in: database)
    try database.replaceDocuments(folderID: id, with: [file("a.md", hash: "1"), file("b.md", hash: "2")], firstScan: true)
    try database.replaceDocuments(folderID: id, with: [file("a.md", hash: "1")], firstScan: false)
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
    #expect(names.contains { $0.hasPrefix("library-broken-") })
}

@Test func folderColorsSkipColorsInUse() {
    #expect(FolderColor.next(after: []) == .blue)
    #expect(FolderColor.next(after: [.blue, .indigo]) == .purple)
    #expect(!FolderColor.allCases.map(\.rawValue).contains("green"))
}
