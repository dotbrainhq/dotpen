import SwiftUI

@main
struct DotMDApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownFile.self) { configuration in
            ScrollView {
                Text(configuration.document.text)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(minWidth: 560, minHeight: 480)
        }
    }
}
