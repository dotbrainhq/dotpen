import AppKit
import DotMDCore
import Observation
import SwiftUI

/// Asks the Files window to show a document, from outside it: the menu bar item uses this.
@MainActor
@Observable
final class FilesNavigator {
    /// The document the Files window should select next. It clears this once it has.
    var requested: Int64?
}

/// The prototype's menu bar menu: who is writing now, new and changed files, then Open DotMD, Pause watching and
/// Settings. A native menu, as the prototype draws one.
struct MenuBarMenu: View {
    @Environment(Library.self) private var library
    @Environment(AgentActivity.self) private var activity
    @Environment(FilesNavigator.self) private var navigator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let writing = activity.writingSessions.first {
            let url = URL(fileURLWithPath: writing.write.path)
            Button {
                open(url)
            } label: {
                Text("\(writing.session.agent.name) is writing")
                Text([library.folder(containing: url)?.folder.name, url.lastPathComponent].compactMap(\.self).joined(separator: " · "))
            }
            Divider()
        }
        Section("New and changed") {
            let documents = newAndChanged
            if documents.isEmpty {
                Text("You're all caught up")
            }
            ForEach(documents) { document in
                Button {
                    show(document)
                } label: {
                    Text(document.title ?? (document.relativePath as NSString).lastPathComponent)
                    Text(document.readState == .new ? "new" : "changed")
                }
            }
        }
        Divider()
        Button("Open DotMD") { openFiles() }
            .keyboardShortcut("o")
        if let until = library.pausedUntil {
            Button("Resume watching (paused until \(until.formatted(date: .omitted, time: .shortened)))") {
                Task { await library.resumeWatching() }
            }
        } else {
            Button("Pause watching for 1 hour") { library.pauseWatching(for: .seconds(3600)) }
        }
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate()
        }
        .keyboardShortcut(",")
    }

    /// The five most recent files you haven't read since they arrived or changed.
    private var newAndChanged: [DotMDCore.Document] {
        library.folders.flatMap(\.documents)
            .filter { $0.readState != .read }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(5)
            .map(\.self)
    }

    private func show(_ document: DotMDCore.Document) {
        navigator.requested = document.key
        openFiles()
    }

    private func open(_ url: URL) {
        if let document = library.document(at: url) { show(document) } else { FileActions.openInNewWindow(url) }
    }

    private func openFiles() {
        openWindow(id: "files")
        NSApp.activate()
    }
}
