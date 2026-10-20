import AppKit
import SwiftUI

struct ShareMenu: View {
    let exporter: DocumentExporter
    let fileURL: URL?
    let markdown: String

    var body: some View {
        Menu {
            Button("Export as PDF…") { exporter.export(as: .pdf) }
            Button("Export as HTML…") { exporter.export(as: .html) }
            Divider()
            Button("Copy as Markdown") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            }
            if let fileURL {
                Divider()
                ShareLink(item: fileURL) { Text("Share…") }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .help("Share, export as PDF or HTML")
    }
}
