import Foundation
import Testing
@testable import DotMDCore

private func document(_ path: String, title: String? = nil, minutesAgo: Double = 0, state: ReadState = .read, pinned: Bool = false) -> Document {
    let file = ScannedFile(relativePath: path, title: title, kind: .other, contentHash: "now", modifiedAt: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60))
    var document = Document(folderID: 1, file: file, readHash: state == .read ? "now" : state == .changed ? "before" : nil)
    document.id = Int64(abs(path.hashValue % 100_000))
    document.pinned = pinned
    return document
}

@Test func subfoldersComeFirstThenRootFiles() {
    let groups = FileTree.groups(for: [
        document("README.md"),
        document("docs/specs/api.md"),
        document("docs/plans/rollout.md"),
        document("CLAUDE.md"),
    ], sort: .name, filter: FileFilter())
    #expect(groups.map(\.path) == ["docs/plans", "docs/specs", ""])
    #expect(groups.last?.documents.map(\.fileName) == ["CLAUDE.md", "README.md"])
}

@Test func lastChangedPutsRecentFilesFirst() {
    let groups = FileTree.groups(for: [
        document("old.md", minutesAgo: 60),
        document("new.md", minutesAgo: 1),
    ], sort: .lastChanged, filter: FileFilter())
    #expect(groups.first?.documents.map(\.fileName) == ["new.md", "old.md"])
}

@Test func pinnedFilesStayOnTop() {
    let groups = FileTree.groups(for: [
        document("b.md", minutesAgo: 1),
        document("a.md", minutesAgo: 60, pinned: true),
    ], sort: .lastChanged, filter: FileFilter())
    #expect(groups.first?.documents.map(\.fileName) == ["a.md", "b.md"])
}

@Test func nameSortIsNaturalAndCaseInsensitive() {
    let groups = FileTree.groups(for: [document("step-10.md"), document("Step-2.md"), document("alpha.md")], sort: .name, filter: FileFilter())
    #expect(groups.first?.documents.map(\.fileName) == ["alpha.md", "Step-2.md", "step-10.md"])
}

@Test func queryMatchesPathsAndTitles() {
    var filter = FileFilter()
    filter.query = "bucket"
    let groups = FileTree.groups(for: [
        document("docs/specs/token-bucket.md"),
        document("rate.md", title: "Bucket sizes"),
        document("README.md"),
    ], sort: .name, filter: filter)
    #expect(groups.flatMap(\.documents).map(\.fileName).sorted() == ["rate.md", "token-bucket.md"])
    #expect(filter.isActive)
}

@Test func unreadAndChangedToggles() {
    let documents = [document("read.md"), document("new.md", state: .new), document("changed.md", state: .changed)]
    var filter = FileFilter()
    filter.unreadOnly = true
    #expect(FileTree.groups(for: documents, sort: .name, filter: filter).flatMap(\.documents).map(\.fileName) == ["changed.md", "new.md"])
    filter.unreadOnly = false
    filter.changedOnly = true
    #expect(FileTree.groups(for: documents, sort: .name, filter: filter).flatMap(\.documents).map(\.fileName) == ["changed.md"])
}

@Test func anEmptyFilterIsInactive() {
    #expect(!FileFilter().isActive)
}
