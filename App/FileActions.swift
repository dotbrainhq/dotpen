import AppKit
import DotPenCore

/// An editor dotPen can hand a file to.
struct ExternalEditor: Identifiable {
    let name: String
    let url: URL
    var id: String { name }
}

@MainActor
enum FileActions {
    static func openInNewWindow(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    static func openFilePanel() {
        NSDocumentController.shared.openDocument(nil)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    /// Cursor and VS Code, when they are installed.
    static var editors: [ExternalEditor] {
        [("Cursor", "com.todesktop.230313mzl4w4u92"), ("VS Code", "com.microsoft.VSCode")].compactMap { name, bundleID in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { ExternalEditor(name: name, url: $0) }
        }
    }

    static func open(_ url: URL, in editor: ExternalEditor) {
        NSWorkspace.shared.open([url], withApplicationAt: editor.url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// Starts watching a folder and tells the person when that fails.
    static func watch(_ url: URL, in library: Library) {
        Task {
            do {
                try await library.addFolder(url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "dotPen couldn't watch this folder"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}
