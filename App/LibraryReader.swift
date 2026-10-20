import DotMDCore
import SwiftUI

/// Reads a library file and hands it to the reader. The file's folder is already open through its bookmark.
struct LibraryReader: View {
    @Environment(Library.self) private var library
    let document: DotMDCore.Document
    @State private var text: String?
    @State private var failed = false

    var body: some View {
        let url = library.url(for: document)
        Group {
            if let text, let url {
                ReaderScreen(text: text, fileURL: url)
            } else if failed {
                ContentUnavailableView("DotMD couldn't open this file", systemImage: "doc.questionmark", description: Text(document.relativePath))
            } else {
                Color.clear
            }
        }
        .task(id: LoadKey(url: url, contentHash: document.contentHash)) { await load(url) }
    }

    private struct LoadKey: Equatable {
        let url: URL?
        let contentHash: String
    }

    /// Reads off the main actor. A new URL or content hash starts a fresh attempt.
    private func load(_ url: URL?) async {
        guard let url else {
            failed = true
            return
        }
        failed = false
        let data = await Task.detached { try? Data(contentsOf: url) }.value
        guard let data else {
            failed = true
            return
        }
        text = String(decoding: data, as: UTF8.self)
    }
}
