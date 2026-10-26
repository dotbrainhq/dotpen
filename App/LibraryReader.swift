import DotMDCore
import SwiftUI

/// Reads a library file and hands it to the reader. The file's folder is already open through its bookmark.
struct LibraryReader: View {
    @Environment(Library.self) private var library
    let document: DotMDCore.Document
    let openDocument: (URL) -> ()
    /// Close on the deleted-file notice: the Files window lets go of the file.
    var close: () -> () = {}
    /// J and K on the page.
    var stepFile: (Int) -> () = { _ in }
    var takesFocus = false
    @Environment(\.filesChrome) private var filesChrome
    @State private var text: String?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        let url = library.url(for: document)
        Group {
            if let folder = library.folders.first(where: { $0.id == document.folderID }), folder.accessLost {
                VStack(spacing: 0) {
                    if let filesChrome {
                        TopBar(chrome: filesChrome, title: document.title ?? document.relativePath, path: folder.folder.name + "/" + document.relativePath) {
                            EmptyView()
                        }
                    }
                    AccessLostView(folder: folder)
                }
            } else if let text, let url {
                ReaderScreen(text: text, fileURL: url, onOpenDocument: openDocument, onClose: close, onStepFile: stepFile, takesFocus: takesFocus)
            } else if failed {
                ContentUnavailableView(
                    "This file won't open",
                    systemImage: "doc.questionmark",
                    description: Text("dotPen couldn't read \(document.relativePath). It tries again as soon as the file changes.")
                )
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
