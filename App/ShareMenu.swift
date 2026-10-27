import AppKit
import DotPenRender
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
            Button("Print…") { exporter.print() }
                .disabled(!canExport)
            Divider()
            Button("Copy for Slack") { copy(for: .slack) }
                .disabled(!canExport)
            Button("Copy for Google Docs") { copy(for: .docs) }
                .disabled(!canExport)
            Button("Copy as Markdown") { exporter.copyMarkdown() }
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
        .help("Share, export as PDF or HTML, or print")
    }

    /// The page as HTML shaped for where it's going, with the Markdown as plain text for anything that takes only
    /// text. The Mac beeps if the page can't be read.
    private func copy(for target: CopyTarget) {
        let controller = exporter.controller
        let markdown = markdown
        Task { @MainActor in
            guard let html = try? await controller.copyHTML(for: target), !html.isEmpty else {
                NSSound.beep()
                return
            }
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(html, forType: .html)
            board.setString(markdown, forType: .string)
        }
    }
}
