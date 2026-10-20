import Foundation
import Testing
@testable import DotMDCore

@MainActor
private func makeLibrary() throws -> Library {
    Library(database: try .inMemory())
}

@MainActor @Test func addingAFolderIndexesItsMarkdown() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("docs/plans/rollout.md", "# Rollout")
    try temp.write("node_modules/pkg/README.md", "# Dependency")
    try temp.write("main.swift", "print(1)")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let folder = try #require(library.folders.first)
    #expect(folder.url?.path == temp.url.path)
    #expect(Set(folder.documents.map(\.relativePath)) == ["README.md", "docs/plans/rollout.md"])
    #expect(folder.documents.allSatisfy { $0.readState == .read })
    #expect(folder.ignored == ["node_modules"])
    #expect(folder.unreadCount == 0)
}

@MainActor @Test func addingTheSameFolderTwiceKeepsOne() async throws {
    let temp = try TempFolder()
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    try await library.addFolder(temp.url)
    #expect(library.folders.count == 1)
}

@MainActor @Test func newFilesAreNewAndBeingWritten() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    library.writingQuietPeriod = .milliseconds(100)
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    let file = try temp.write("HANDOFF.md", "# Handoff")
    await library.handle([file.path], in: id)
    let document = try #require(library.folders.first?.documents.first { $0.relativePath == "HANDOFF.md" })
    #expect(document.readState == .new)
    #expect(document.title == "Handoff")
    #expect(library.writing.contains(document.key))
    try await Task.sleep(for: .milliseconds(400))
    #expect(!library.writing.contains(document.key))
}

@MainActor @Test func changedFilesStayChangedUntilRead() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    let file = try temp.write("README.md", "# Repo\n\nMore detail.")
    await library.handle([file.path], in: id)
    var document = try #require(library.folders.first?.documents.first)
    #expect(document.readState == .changed)
    #expect(library.folders.first?.unreadCount == 1)
    library.markRead(document)
    document = try #require(library.folders.first?.documents.first)
    #expect(document.readState == .read)
    library.markUnread(document)
    #expect(library.folders.first?.documents.first?.readState == .new)
}

@MainActor @Test func deletedFilesLeaveTheList() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("old.md", "# Old")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    try temp.remove("old.md")
    await library.handle([temp.url.appending(path: "old.md").path], in: id)
    #expect(library.folders.first?.documents.map(\.relativePath) == ["README.md"])
}

@MainActor @Test func eventsInsideIgnoredFoldersAreSkipped() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    let file = try temp.write("node_modules/pkg/CHANGELOG.md", "# Changes")
    await library.handle([file.path], in: id)
    #expect(library.folders.first?.documents.map(\.relativePath) == ["README.md"])
}

@MainActor @Test func aNewFolderTriggersARescan() async throws {
    let temp = try TempFolder()
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    try temp.write("docs/specs/api.md", "# API")
    await library.handle([temp.url.appending(path: "docs").path], in: id)
    #expect(library.folders.first?.documents.map(\.relativePath) == ["docs/specs/api.md"])
}

@MainActor @Test func pinning() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let document = try #require(library.folders.first?.documents.first)
    library.setPinned(document, true)
    #expect(library.folders.first?.documents.first?.pinned == true)
}

@MainActor @Test func filesAreFoundByURL() async throws {
    let temp = try TempFolder()
    let file = try temp.write("docs/plan.md", "# Plan")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    #expect(library.document(at: file)?.relativePath == "docs/plan.md")
    #expect(library.folder(containing: file)?.url?.path == temp.url.path)
    let document = try #require(library.document(at: file))
    #expect(library.url(for: document)?.path == file.path)
}

@MainActor @Test func removingAFolderForgetsIt() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.removeFolder(id)
    #expect(library.folders.isEmpty)
}

@MainActor @Test func restartingFindsChangesMadeWhileClosed() async throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    let database = try LibraryDatabase.inMemory()
    let first = Library(database: database)
    try await first.addFolder(temp.url)
    first.removeFolderWatchersForTesting()
    try temp.write("README.md", "# Repo, edited while DotMD was closed")
    let second = Library(database: database)
    await second.start()
    #expect(second.folders.first?.documents.first?.readState == .changed)
}

@MainActor @Test func colorsCanChange() async throws {
    let temp = try TempFolder()
    let library = try makeLibrary()
    try await library.addFolder(temp.url)
    let id = try #require(library.folders.first?.id)
    library.setColor(.orange, for: id)
    #expect(library.folders.first?.folder.color == .orange)
}
