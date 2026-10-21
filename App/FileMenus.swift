import DotMDCore
import SwiftUI

struct FileMenu: View {
    @Environment(Library.self) private var library
    let document: DotMDCore.Document

    var body: some View {
        if let url = library.url(for: document) {
            Button("Open in new window") { FileActions.openInNewWindow(url) }
            ForEach(FileActions.editors) { editor in
                Button("Open in \(editor.name)") { FileActions.open(url, in: editor) }
            }
            Divider()
            Button("Reveal in Finder") { FileActions.reveal(url) }
            Button("Copy path") { FileActions.copyPath(url) }
            Divider()
            if document.readState == .read {
                Button("Mark as unread") { library.markUnread(document) }
            } else {
                Button("Mark as read") { Task { await library.markRead(document) } }
            }
            Button(document.pinned ? "Unpin" : "Pin to top") { library.setPinned(document, !document.pinned) }
            Divider()
            ShareLink(item: url)
        }
    }
}

struct FolderMenu: View {
    @Environment(Library.self) private var library
    let folder: FolderState

    var body: some View {
        Picker("Color", selection: color) {
            ForEach(FolderColor.allCases, id: \.self) { color in
                Text(color.name).tag(color)
            }
        }
        if let url = folder.url {
            Button("Reveal in Finder") { FileActions.reveal(url) }
            Button("Copy path") { FileActions.copyPath(url) }
        } else {
            Button("Choose folder…", action: reconnect)
        }
        Divider()
        Button("Stop watching") { library.removeFolder(folder.id) }
    }

    private var color: Binding<FolderColor> {
        Binding(get: { folder.folder.color }, set: { library.setColor($0, for: folder.id) })
    }

    private func reconnect() {
        let parent = URL(fileURLWithPath: folder.folder.path).deletingLastPathComponent()
        guard let url = FolderPicker.chooseFolder(
            message: "DotMD lost access to \(folder.folder.name). Choose it again to keep watching it.",
            prompt: "Choose",
            startingAt: parent
        ) else { return }
        Task { try? await library.reconnect(folder.id, to: url) }
    }
}
