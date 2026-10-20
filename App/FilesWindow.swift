import AppKit
import DotMDCore
import SwiftUI

/// The Files layout: watched folders on the left, the selected document on the right.
struct FilesWindow: View {
    @Environment(Library.self) private var library
    @State private var selection: Int64?
    @State private var columns = NavigationSplitViewVisibility.all
    @AppStorage("fileSort") private var sort = FileSortOrder.lastChanged
    @AppStorage("showTitles") private var showTitles = true
    @State private var filter = FileFilter()

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            FileList(selection: $selection, sort: sort, showTitles: showTitles, filter: filter)
                .safeAreaInset(edge: .top, spacing: 0) {
                    ListHeader(sort: $sort, showTitles: $showTitles)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FilterBar(filter: $filter, addFolder: addFolder)
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 420)
        } detail: {
            detail
        }
        .focusedSceneValue(\.toggleFiles, toggleFiles)
        .frame(minWidth: 760, minHeight: 480)
    }

    private var selectedDocument: DotMDCore.Document? {
        guard let selection else { return nil }
        return library.folders.lazy.flatMap(\.documents).first { $0.key == selection }
    }

    @ViewBuilder private var detail: some View {
        if let document = selectedDocument {
            LibraryReader(document: document)
                .id(document.key)
        } else if library.folders.isEmpty {
            ContentUnavailableView {
                Label("No folders yet", systemImage: "folder.badge.plus")
            } description: {
                Text("Watch a folder and DotMD lists every Markdown file inside it.")
            } actions: {
                Button("Watch a folder…", action: addFolder)
            }
        } else {
            ContentUnavailableView("Choose a file", systemImage: "doc.text", description: Text("Pick a Markdown file from the list."))
        }
    }

    private func toggleFiles() {
        columns = columns == .detailOnly ? .all : .detailOnly
    }

    private func addFolder() {
        guard let url = FolderPicker.chooseFolder(message: "Choose a folder to watch. DotMD lists every Markdown file inside it.") else { return }
        FileActions.watch(url, in: library)
    }
}

extension FocusedValues {
    @Entry var toggleFiles: (() -> ())?
}

/// View > Show Files (⌥⌘S): hides or shows the file list in the Files window, or opens that window from a document window.
struct FilesCommands: Commands {
    @FocusedValue(\.toggleFiles) private var toggleFiles
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(toggleFiles == nil ? "Show Files" : "Show or Hide Files") {
                if let toggleFiles { toggleFiles() } else { openWindow(id: "files") }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }
    }
}
