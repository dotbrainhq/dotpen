import DotMDCore
import SwiftUI

@main
struct DotMDApp: App {
    @State private var library = Library.makeDefault()

    var body: some Scene {
        Window("DotMD", id: "files") {
            FilesWindow()
                .environment(library)
                .task {
                    await library.start()
                    #if DEBUG
                    await DebugWorkspace.open(in: library)
                    #endif
                }
        }
        // The prototype's window: 1200 by 806, with no title bar over the sidebar panel.
        .defaultSize(width: 1200, height: 806)
        .windowStyle(.hiddenTitleBar)
        .commands {
            FilesCommands()
        }

        DocumentGroup(viewing: MarkdownFile.self) { configuration in
            ReaderScreen(text: configuration.document.text, fileURL: configuration.fileURL)
                .background(WindowTabbing())
                .frame(minWidth: 560, minHeight: 480)
                .environment(library)
                .task { await library.start() }
        }
        .commands { ExportCommands() }
    }
}
