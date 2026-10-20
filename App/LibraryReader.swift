import DotMDCore
import SwiftUI

/// Reads a library file and hands it to the reader. The file's folder is already open through its bookmark.
struct LibraryReader: View {
    @Environment(Library.self) private var library
    let document: DotMDCore.Document
    @State private var text: String?
    @State private var failed = false
    @State private var attempt = 0

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
        .task(id: LoadKey(url: url, attempt: attempt)) { await load(url) }
        .onChange(of: document.contentHash) {
            // A content change reloads through the reader's own watcher; only a failed load needs another try.
            if failed { attempt += 1 }
        }
    }

    private struct LoadKey: Equatable {
        let url: URL?
        let attempt: Int
    }

    /// Reads off the main actor. A new URL, or a content change after a failure, starts a fresh attempt.
    private func load(_ url: URL?) async {
        guard let url else {
            failed = true
            return
        }
        failed = false
        let data = await Task.detached { try? Data(contentsOf: url) }.value
        guard !Task.isCancelled else { return }
        guard let data else {
            failed = true
            return
        }
        text = String(decoding: data, as: UTF8.self)
    }
}
