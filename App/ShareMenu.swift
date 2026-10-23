import AppKit
import SwiftUI

struct ShareMenu: View {
    let exporter: DocumentExporter
    /// Off while the reader shows the source: export draws the page.
    var canExport = true
    let fileURL: URL?
    let markdown: String

    var body: some View {
        Menu {
            Button("Export as PDF…") { exporter.export(as: .pdf) }
                .disabled(!canExport)
            Button("Export as HTML…") { exporter.export(as: .html) }
                .disabled(!canExport)
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
                // Not Icon, which hides itself from VoiceOver: drawn icon-only, the menu takes its name from here.
                Image("Icons/share")
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .accessibilityLabel("Share")
            }
        }
        // The prototype draws share as a plain button, with no menu arrow beside it.
        .menuIndicator(.hidden)
        .help("Share, export as PDF or HTML")
    }
}
