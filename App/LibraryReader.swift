import DotMDCore
import SwiftUI

/// Reads a library file and hands it to the reader. The file's folder is already open through its bookmark.
struct LibraryReader: View {
    @Environment(Library.self) private var library
    let document: DotMDCore.Document
    @State private var text: String?
    @State private var failed = false

    var body: some View {
        Group {
            if let text, let url = library.url(for: document) {
                ReaderScreen(text: text, fileURL: url)
            } else if failed {
                ContentUnavailableView("DotMD couldn't open this file", systemImage: "doc.questionmark", description: Text(document.relativePath))
            } else {
                Color.clear
            }
        }
        .task { load() }
    }

    private func load() {
        guard let url = library.url(for: document), let data = try? Data(contentsOf: url) else {
            failed = true
            return
        }
        text = String(decoding: data, as: UTF8.self)
    }
}
