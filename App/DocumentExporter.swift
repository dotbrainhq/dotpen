import AppKit
import DotPenRender
import SwiftUI
import UniformTypeIdentifiers

/// Exports, prints and copies the focused reader window. The share menu and the app's menus all go through it.
@MainActor
struct DocumentExporter {
    let controller: ReaderController
    let title: String
    let options: ReadingOptions
    /// The file as written.
    let markdown: String

    func print() {
        Task { @MainActor in await PDFExport.print(webView: controller.webView) }
    }

    func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    func export(as type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        let base = (title as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + (type == .pdf ? ".pdf" : ".html")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                if type == .pdf {
                    try await PDFExport.write(webView: controller.webView, to: url)
                } else {
                    try await HTMLExport.write(from: controller, title: base, options: options, to: url)
                }
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "dotPen couldn't export this file"
                alert.runModal()
            }
        }
    }
}

extension FocusedValues {
    @Entry var documentExporter: DocumentExporter?
}

struct ExportCommands: Commands {
    @FocusedValue(\.documentExporter) private var exporter

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export as PDF…") { exporter?.export(as: .pdf) }
                .keyboardShortcut("e")
                .disabled(exporter == nil)
            Button("Export as HTML…") { exporter?.export(as: .html) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(exporter == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { exporter?.print() }
                .keyboardShortcut("p")
                .disabled(exporter == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy as Markdown") { exporter?.copyMarkdown() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(exporter == nil)
        }
    }
}
