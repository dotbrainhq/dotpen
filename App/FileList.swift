import DotMDCore
import SwiftUI

struct FileList: View {
    @Environment(Library.self) private var library
    @Binding var selection: Int64?
    let sort: FileSortOrder
    let showTitles: Bool
    let filter: FileFilter
    @State private var collapsed: Set<String> = []

    var body: some View {
        List(selection: $selection) {
            ForEach(library.folders) { folder in
                let groups = FileTree.groups(for: folder.documents, sort: sort, filter: filter)
                if !filter.isActive || !groups.isEmpty {
                    DisclosureGroup(isExpanded: expanded("\(folder.id)")) {
                        ForEach(groups) { group in
                            if group.path.isEmpty {
                                rows(group.documents)
                            } else {
                                DisclosureGroup(isExpanded: expanded("\(folder.id)/\(group.path)")) {
                                    rows(group.documents)
                                } label: {
                                    Label(group.path, systemImage: "folder")
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        if folder.documents.isEmpty && !folder.accessLost {
                            Text("No Markdown files yet")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        FolderRow(folder: folder)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func rows(_ documents: [DotMDCore.Document]) -> some View {
        ForEach(documents) { document in
            FileRow(document: document, showTitles: showTitles, isWriting: library.writing.contains(document.key))
                .tag(document.key)
        }
    }

    private func expanded(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(key) },
            set: { isOpen in
                if isOpen { collapsed.remove(key) } else { collapsed.insert(key) }
            }
        )
    }
}
