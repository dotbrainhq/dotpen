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
                FolderSection(
                    folder: folder,
                    sort: sort,
                    showTitles: showTitles,
                    filter: filter,
                    collapsed: collapsedKeys(in: folder),
                    setExpanded: setExpanded
                )
                .equatable()
            }
        }
        .listStyle(.sidebar)
    }

    /// Only this folder's keys, so another folder's toggle leaves this section unchanged.
    private func collapsedKeys(in folder: FolderState) -> Set<String> {
        let own = "\(folder.id)"
        return collapsed.filter { $0 == own || $0.hasPrefix(own + "/") }
    }

    private func setExpanded(_ key: String, _ isOpen: Bool) {
        if isOpen { collapsed.remove(key) } else { collapsed.insert(key) }
    }
}

/// One watched folder and its files. SwiftUI skips its body while the folder, the list settings and its own
/// collapsed keys are unchanged, so a change in one folder doesn't regroup the others.
struct FolderSection: View, Equatable {
    let folder: FolderState
    let sort: FileSortOrder
    let showTitles: Bool
    let filter: FileFilter
    let collapsed: Set<String>
    let setExpanded: (String, Bool) -> Void

    nonisolated static func == (lhs: FolderSection, rhs: FolderSection) -> Bool {
        lhs.folder == rhs.folder && lhs.sort == rhs.sort && lhs.showTitles == rhs.showTitles
            && lhs.filter == rhs.filter && lhs.collapsed == rhs.collapsed
    }

    var body: some View {
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

    private func rows(_ documents: [DotMDCore.Document]) -> some View {
        ForEach(documents) { document in
            FileRow(document: document, showTitles: showTitles)
                .tag(document.key)
        }
    }

    private func expanded(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(key) },
            set: { setExpanded(key, $0) }
        )
    }
}
