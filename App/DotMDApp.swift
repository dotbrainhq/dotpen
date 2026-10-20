import SwiftUI

@main
struct DotMDApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownFile.self) { configuration in
            ReaderScreen(file: configuration.document, fileURL: configuration.fileURL)
                .frame(minWidth: 560, minHeight: 480)
        }
    }
}
