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
            Label {
                Text("Share")
            } icon: {
                Icon("share", size: 16)
            }
        }
        // The prototype draws share as a plain button, with no menu arrow beside it.
        .menuIndicator(.hidden)
        .help("Share, export as PDF or HTML")
    }
}
