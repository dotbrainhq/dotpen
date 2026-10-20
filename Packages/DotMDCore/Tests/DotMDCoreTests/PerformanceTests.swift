import Foundation
import Testing
@testable import DotMDCore

/// The spec's budget: index 5,000 files in under 5 seconds on an M1. Runs only with DOTMD_PERF=1,
/// so CI and everyday test runs stay fast.
@Test(.enabled(if: ProcessInfo.processInfo.environment["DOTMD_PERF"] == "1"))
func indexesFiveThousandFilesInUnderFiveSeconds() throws {
    let temp = try TempFolder()
    let body = String(repeating: "Some text about the rollout. ", count: 60)
    for index in 0..<5_000 {
        try temp.write("docs/\(index % 50)/note-\(index).md", "# Note \(index)\n\n\(body)")
    }
    let database = try LibraryDatabase.inMemory()
    let folder = try database.insert(WatchedFolder(bookmark: Data(), path: temp.url.path, name: "perf", color: .blue))
    let elapsed = ContinuousClock().measure {
        guard let result = FolderScanner.scan(root: temp.url, rules: .load(root: temp.url)) else { return }
        try? database.replaceDocuments(folderID: folder.id ?? 0, with: result.files)
    }
    #expect(try database.documents(folderID: folder.id ?? 0).count == 5_000)
    #expect(elapsed < .seconds(5), "Indexing took \(elapsed)")
}
