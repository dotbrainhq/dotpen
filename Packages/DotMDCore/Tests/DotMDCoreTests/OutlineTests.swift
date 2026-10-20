import Foundation
import Testing
@testable import DotMDCore

private func document(_ path: String, key: Int64, title: String? = nil, state: ReadState = .read) -> Document {
    let file = ScannedFile(relativePath: path, title: title, kind: .other, contentHash: "now", modifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
    var document = Document(folderID: 1, file: file, readHash: state == .read ? "now" : state == .changed ? "before" : nil)
    document.id = key
    return document
}

private func folder(_ id: Int64, _ name: String, documents: [Document] = [], ignored: [String] = []) -> FolderState {
    let watched = WatchedFolder(id: id, bookmark: Data(), path: "/tmp/\(name)", name: name, color: .blue)
    return FolderState(folder: watched, status: .ready, documents: documents, ignored: ignored)
}

private let gateway = folder(1, "api-gateway", documents: [
    document("README.md", key: 10, title: "API Gateway"),
    document("docs/plans/rate-limiter.md", key: 11, title: "Rate limiter rollout", state: .new),
    document("docs/specs/token-bucket.md", key: 12, state: .changed),
])

@Test func rowsFollowTheOutlineOrder() {
    let rows = Outline.rows(for: [gateway], sort: .name, filter: FileFilter(), showTitles: false, collapsed: [])
    #expect(rows.map(\.name) == ["api-gateway", "docs/plans", "rate-limiter.md", "docs/specs", "token-bucket.md", "README.md"])
    #expect(rows.map(\.depth) == [0, 1, 2, 1, 2, 1])
    #expect(rows[2].parent == .directory(folder: 1, path: "docs/plans"))
    #expect(rows[5].parent == .folder(1))
}

@Test func collapsedRowsHideTheirChildren() {
    let rows = Outline.rows(for: [gateway], sort: .name, filter: FileFilter(), showTitles: false, collapsed: ["1/docs/plans"])
    #expect(rows.map(\.name) == ["api-gateway", "docs/plans", "docs/specs", "token-bucket.md", "README.md"])
    #expect(rows[1].isExpanded == false)
    let closed = Outline.rows(for: [gateway], sort: .name, filter: FileFilter(), showTitles: false, collapsed: ["1"])
    #expect(closed.map(\.id) == [.folder(1)])
}

@Test func titlesNameFileRowsWhenShown() {
    let rows = Outline.rows(for: [gateway], sort: .name, filter: FileFilter(), showTitles: true, collapsed: [])
    #expect(rows.last?.name == "API Gateway")
    #expect(rows[4].name == "token-bucket.md")
}

@Test func filterDropsFoldersWithNoMatches() {
    var filter = FileFilter()
    filter.unreadOnly = true
    let empty = folder(2, "web-app", documents: [document("NOTES.md", key: 20)])
    let rows = Outline.rows(for: [gateway, empty], sort: .name, filter: filter, showTitles: false, collapsed: [])
    #expect(rows.map(\.name) == ["api-gateway", "docs/plans", "rate-limiter.md", "docs/specs", "token-bucket.md"])
    let unfiltered = Outline.rows(for: [folder(3, "dotmd")], sort: .name, filter: FileFilter(), showTitles: false, collapsed: [])
    #expect(unfiltered.map(\.name) == ["dotmd"])
}

@Test func moveStopsAtTheEnds() {
    let rows = Outline.rows(for: [gateway], sort: .name, filter: FileFilter(), showTitles: false, collapsed: [])
    #expect(Outline.move(from: nil, by: 1, in: rows) == .folder(1))
    #expect(Outline.move(from: nil, by: -1, in: rows) == .file(folder: 1, key: 10))
    #expect(Outline.move(from: .folder(1), by: -1, in: rows) == .folder(1))
    #expect(Outline.move(from: .folder(1), by: 2, in: rows) == .file(folder: 1, key: 11))
    #expect(Outline.move(from: .file(folder: 1, key: 10), by: 1, in: rows) == .file(folder: 1, key: 10))
}

@Test func typeSelectFindsTheNextMatchAndWraps() {
    let rows = Outline.rows(for: [gateway], sort: .name, filter: FileFilter(), showTitles: false, collapsed: [])
    #expect(Outline.typeSelect("d", from: nil, includingFocus: false, in: rows) == .directory(folder: 1, path: "docs/plans"))
    #expect(Outline.typeSelect("d", from: .directory(folder: 1, path: "docs/plans"), includingFocus: false, in: rows)
        == .directory(folder: 1, path: "docs/specs"))
    #expect(Outline.typeSelect("D", from: .directory(folder: 1, path: "docs/specs"), includingFocus: false, in: rows)
        == .directory(folder: 1, path: "docs/plans"))
    #expect(Outline.typeSelect("docs/s", from: .directory(folder: 1, path: "docs/specs"), includingFocus: true, in: rows)
        == .directory(folder: 1, path: "docs/specs"))
    #expect(Outline.typeSelect("zz", from: nil, includingFocus: false, in: rows) == nil)
}

@Test func hiddenPathsNameBuiltInsThenCountTheRest() {
    let a = folder(1, "a", ignored: ["node_modules", "packages/web/build", "secret.md", ".git"])
    let b = folder(2, "b", ignored: ["build", "tmp", "drafts/old.md"])
    #expect(HiddenPathsSummary.text(for: [a, b], showIgnored: false) == "Hiding node_modules, build and 3 paths in .gitignore")
    #expect(HiddenPathsSummary.text(for: [folder(1, "a", ignored: ["build", "node_modules"])], showIgnored: false)
        == "Hiding node_modules and build")
    #expect(HiddenPathsSummary.text(for: [folder(1, "a", ignored: ["dist"])], showIgnored: false) == "Hiding dist")
    #expect(HiddenPathsSummary.text(for: [folder(1, "a", ignored: ["x.md"])], showIgnored: false) == "Hiding 1 path in .gitignore")
    #expect(HiddenPathsSummary.text(for: [folder(1, "a", ignored: ["x.md", "y"])], showIgnored: false) == "Hiding 2 paths in .gitignore")
}

@Test func hiddenPathsNoteWhenShownOrEmpty() {
    #expect(HiddenPathsSummary.text(for: [folder(1, "a")], showIgnored: false) == nil)
    #expect(HiddenPathsSummary.text(for: [folder(1, "a", ignored: [".git"])], showIgnored: false) == nil)
    #expect(HiddenPathsSummary.text(for: [folder(1, "a")], showIgnored: true) == "Showing hidden paths")
}
