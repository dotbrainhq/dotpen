import Foundation
import Testing
@testable import DotMDCore

private func scanned(_ path: String, _ text: String) -> ScannedFile {
    let data = Data(text.utf8)
    return ScannedFile(relativePath: path, title: nil, kind: .other, contentHash: Snapshots.hash(data),
                       modifiedAt: Date(timeIntervalSince1970: 1_800_000_000), content: data)
}

private func makeFolder(_ database: LibraryDatabase) throws -> Int64 {
    try database.insert(WatchedFolder(bookmark: Data(), path: "/tmp/repo", name: "repo", color: .blue)).id ?? 0
}

@Test func snapshotsSurviveCompression() {
    let data = Data(String(repeating: "Rate limiter rollout. ", count: 200).utf8)
    let packed = Snapshots.compress(data)
    #expect(packed.count < data.count)
    #expect(Snapshots.decompress(packed) == data)
}

@Test func theFirstScanKeepsWhatCountsAsRead() throws {
    let database = try LibraryDatabase.inMemory()
    let folder = try makeFolder(database)
    let file = scanned("plan.md", "# Plan\n\nFirst version.")
    try database.replaceDocuments(folderID: folder, with: [file])
    #expect(try database.snapshotText(hash: file.contentHash) == "# Plan\n\nFirst version.")
}

@Test func newFilesAfterTheFirstScanHaveNoSnapshot() throws {
    let database = try LibraryDatabase.inMemory()
    let folder = try makeFolder(database)
    try database.replaceDocuments(folderID: folder, with: [scanned("a.md", "# A")])
    let later = scanned("b.md", "# B")
    try database.replaceDocuments(folderID: folder, with: [scanned("a.md", "# A"), later])
    #expect(try database.snapshotText(hash: later.contentHash) == nil)
}

@Test func readFilesFromBeforeSnapshotsGetOneOnTheNextScan() throws {
    let database = try LibraryDatabase.inMemory()
    let folder = try makeFolder(database)
    var file = scanned("plan.md", "# Plan")
    let bytes = file.content
    file.content = Data()
    try database.replaceDocuments(folderID: folder, with: [file])
    #expect(try database.snapshotText(hash: file.contentHash) == nil)
    file.content = bytes
    try database.replaceDocuments(folderID: folder, with: [file])
    #expect(try database.snapshotText(hash: file.contentHash) == "# Plan")
}

@Test func markingReadKeepsOnlyTheLatestReadText() throws {
    let database = try LibraryDatabase.inMemory()
    let folder = try makeFolder(database)
    let first = scanned("plan.md", "# Plan\n\nOne.")
    try database.replaceDocuments(folderID: folder, with: [first])
    let document = try #require(try database.documents(folderID: folder).first)
    let second = Data("# Plan\n\nTwo.".utf8)
    let updated = try #require(try database.markRead(documentID: document.key, content: second))
    #expect(updated.readHash == Snapshots.hash(second))
    #expect(try database.snapshotText(hash: Snapshots.hash(second)) == "# Plan\n\nTwo.")
    #expect(try database.snapshotText(hash: first.contentHash) == nil)
}

@Test func theReadingLineIsStored() throws {
    let database = try LibraryDatabase.inMemory()
    let folder = try makeFolder(database)
    try database.replaceDocuments(folderID: folder, with: [scanned("plan.md", "# Plan")])
    let document = try #require(try database.documents(folderID: folder).first)
    let at = Date(timeIntervalSince1970: 1_800_000_100)
    let updated = try #require(try database.setReadLine(documentID: document.key, line: 42, at: at))
    #expect(updated.readLine == 42)
    #expect(updated.readLineAt == at)
}

@MainActor @Test func theLibraryHandsBackTheTextLastRead() async throws {
    let temp = try TempFolder()
    try temp.write("plan.md", "# Plan\n\nFirst version.")
    let library = Library(database: try .inMemory())
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    let file = try temp.write("plan.md", "# Plan\n\nSecond version.")
    await library.handle([file.path], in: id)
    var document = try #require(library.folders.first?.documents.first)
    #expect(document.readState == .changed)
    #expect(library.lastReadText(for: document) == "# Plan\n\nFirst version.")
    library.markRead(document, text: "# Plan\n\nSecond version.")
    document = try #require(library.folders.first?.documents.first)
    #expect(document.readState == .read)
    #expect(library.lastReadText(for: document) == "# Plan\n\nSecond version.")
}

@MainActor @Test func filesReadByTheFirstScanDateFromWhenTheirTextWasKept() async throws {
    let temp = try TempFolder()
    try temp.write("plan.md", "# Plan\n\nFirst version.")
    let library = Library(database: try .inMemory())
    let before = Date.now.addingTimeInterval(-1)
    try await library.addFolder(temp.url)
    let document = try #require(library.folders.first?.documents.first)
    #expect(document.lastReadAt == nil)
    let date = try #require(library.lastReadDate(for: document))
    #expect(date >= before && date <= .now.addingTimeInterval(1))
}

@MainActor @Test func aReadDateWinsOverTheSnapshotDate() async throws {
    let temp = try TempFolder()
    try temp.write("plan.md", "# Plan")
    let library = Library(database: try .inMemory())
    try await library.addFolder(temp.url)
    var document = try #require(library.folders.first?.documents.first)
    library.markRead(document, text: "# Plan")
    document = try #require(library.folders.first?.documents.first)
    #expect(library.lastReadDate(for: document) == document.lastReadAt)
}
