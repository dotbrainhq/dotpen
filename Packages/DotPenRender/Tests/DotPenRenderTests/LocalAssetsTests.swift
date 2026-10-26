import Foundation
import Testing
@testable import DotPenRender

private func makeRepo() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "dotpen-assets-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appending(path: "docs/plans"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appending(path: "assets"), withIntermediateDirectories: true)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: root.appending(path: "assets/cover.png"))
    try Data("secret".utf8).write(to: root.appending(path: "assets/notes.txt"))
    return root
}

@Test func documentPathsStartAtTheDocumentFolder() throws {
    let root = try makeRepo()
    let documentDirectory = root.appending(path: "docs/plans")
    let url = try #require(URL(string: "dotpen-asset://doc/..%2F..%2Fassets%2Fcover.png"))
    let file = LocalAssetHandler.resolve(url, documentDirectory: documentDirectory, root: root)
    #expect(file?.path == root.appending(path: "assets/cover.png").standardizedFileURL.path)
}

@Test func rootPathsStartAtTheWatchedFolder() throws {
    let root = try makeRepo()
    let url = try #require(URL(string: "dotpen-asset://root/assets%2Fcover.png"))
    #expect(LocalAssetHandler.resolve(url, documentDirectory: root.appending(path: "docs"), root: root) != nil)
}

@Test func nothingOutsideTheRootIsServed() throws {
    let root = try makeRepo()
    let url = try #require(URL(string: "dotpen-asset://doc/..%2F..%2F..%2Fetc%2Fhosts.png"))
    #expect(LocalAssetHandler.resolve(url, documentDirectory: root.appending(path: "docs/plans"), root: root) == nil)
}

@Test func onlyImagesAreServed() throws {
    let root = try makeRepo()
    let url = try #require(URL(string: "dotpen-asset://root/assets%2Fnotes.txt"))
    #expect(LocalAssetHandler.resolve(url, documentDirectory: root, root: root) == nil)
}

@Test func exportedHTMLCarriesLocalImages() throws {
    let root = try makeRepo()
    let html = #"<p><img src="dotpen-asset://root/assets%2Fcover.png" alt="Cover"></p>"#
    let out = HTMLExport.inlineLocalImages(in: html, documentDirectory: root, root: root)
    #expect(out.contains(#"src="data:image/png;base64,iVBORw==""#))
}
