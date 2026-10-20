import Foundation

/// Names one row of the file outline. File rows carry their folder so a section can tell which rows are its own.
public enum OutlineRowID: Hashable, Sendable {
    case folder(Int64)
    case directory(folder: Int64, path: String)
    case file(folder: Int64, key: Int64)

    public var folderID: Int64 {
        switch self {
        case let .folder(id), let .directory(id, _), let .file(id, _): id
        }
    }

    /// The key the outline stores while the row is collapsed. Nil for file rows, which never open.
    public var expansionKey: String? {
        switch self {
        case let .folder(id): "\(id)"
        case let .directory(id, path): "\(id)/\(path)"
        case .file: nil
        }
    }
}

/// One visible row of the file outline, in display order.
public struct OutlineRow: Identifiable, Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case folder
        case directory(path: String)
        case file(Document)
    }

    public var id: OutlineRowID
    public var content: Content
    /// 0 for a watched folder, 1 for a subfolder or a file at the folder root, 2 for a file in a subfolder.
    public var depth: Int
    public var parent: OutlineRowID?
    /// What type-to-select matches against: the folder name, the subfolder path or the file's shown name.
    public var name: String
    /// Open folders and subfolders. Always false for files.
    public var isExpanded: Bool

    public var isExpandable: Bool {
        if case .file = content { return false }
        return true
    }
}

/// Builds the rows the file outline shows, and moves keyboard focus through them.
public enum Outline {
    /// The visible rows of one watched folder: the folder, then its subfolders and files while each is open.
    /// A folder with nothing matching an active filter has no rows at all.
    public static func rows(for folder: FolderState, sort: FileSortOrder, filter: FileFilter, showTitles: Bool,
                            collapsed: Set<String>) -> [OutlineRow] {
        let groups = FileTree.groups(for: folder.documents, sort: sort, filter: filter)
        if filter.isActive && groups.isEmpty { return [] }
        let folderID = OutlineRowID.folder(folder.id)
        let folderOpen = !collapsed.contains(folderID.expansionKey ?? "")
        var rows = [OutlineRow(id: folderID, content: .folder, depth: 0, parent: nil, name: folder.folder.name, isExpanded: folderOpen)]
        guard folderOpen else { return rows }
        for group in groups {
            if group.path.isEmpty {
                rows += files(group.documents, in: folder.id, depth: 1, parent: folderID, showTitles: showTitles)
            } else {
                let id = OutlineRowID.directory(folder: folder.id, path: group.path)
                let open = !collapsed.contains(id.expansionKey ?? "")
                rows.append(OutlineRow(id: id, content: .directory(path: group.path), depth: 1, parent: folderID, name: group.path, isExpanded: open))
                if open {
                    rows += files(group.documents, in: folder.id, depth: 2, parent: id, showTitles: showTitles)
                }
            }
        }
        return rows
    }

    /// Every visible row across the watched folders, in display order.
    public static func rows(for folders: [FolderState], sort: FileSortOrder, filter: FileFilter, showTitles: Bool,
                            collapsed: Set<String>) -> [OutlineRow] {
        folders.flatMap { rows(for: $0, sort: sort, filter: filter, showTitles: showTitles, collapsed: collapsed) }
    }

    private static func files(_ documents: [Document], in folderID: Int64, depth: Int, parent: OutlineRowID,
                              showTitles: Bool) -> [OutlineRow] {
        documents.map { document in
            OutlineRow(id: .file(folder: folderID, key: document.key), content: .file(document), depth: depth, parent: parent,
                       name: document.displayName(showTitles: showTitles), isExpanded: false)
        }
    }

    /// The row offset steps away from focus, stopping at either end. With nothing focused, Down picks the first
    /// row and Up the last.
    public static func move(from focus: OutlineRowID?, by offset: Int, in rows: [OutlineRow]) -> OutlineRowID? {
        guard !rows.isEmpty else { return nil }
        guard let focus, let index = rows.firstIndex(where: { $0.id == focus }) else {
            return offset >= 0 ? rows.first?.id : rows.last?.id
        }
        return rows[min(max(index + offset, 0), rows.count - 1)].id
    }

    /// The next row whose name starts with prefix, ignoring case, wrapping past the end. A new prefix starts after
    /// the focused row so repeating a letter cycles; a longer prefix keeps the focused row if it still matches.
    public static func typeSelect(_ prefix: String, from focus: OutlineRowID?, includingFocus: Bool,
                                  in rows: [OutlineRow]) -> OutlineRowID? {
        guard !prefix.isEmpty, !rows.isEmpty else { return nil }
        let start = focus.flatMap { id in rows.firstIndex { $0.id == id } }
        let first = start.map { includingFocus ? $0 : $0 + 1 } ?? 0
        for step in 0..<rows.count {
            let row = rows[(first + step) % rows.count]
            if row.name.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
                return row.id
            }
        }
        return nil
    }
}

/// The sentence at the end of the file outline about paths the ignore rules hide.
public enum HiddenPathsSummary {
    /// "Hiding node_modules, build and 214 paths in .gitignore", "Showing hidden paths" while they are shown,
    /// or nil when nothing is hidden.
    public static func text(for folders: [FolderState], showIgnored: Bool) -> String? {
        if showIgnored { return "Showing hidden paths" }
        var foundNames: Set<String> = []
        var otherCount = 0
        for folder in folders {
            for path in folder.ignored {
                let name = (path as NSString).lastPathComponent
                if name == ".git" { continue }
                if IgnoreRules.builtInDirectories.contains(name) {
                    foundNames.insert(name)
                } else {
                    otherCount += 1
                }
            }
        }
        var parts = IgnoreRules.builtInDirectoryNames.filter { foundNames.contains($0) }
        if otherCount > 0 {
            parts.append(otherCount == 1 ? "1 path in .gitignore" : "\(otherCount) paths in .gitignore")
        }
        guard let last = parts.popLast() else { return nil }
        return "Hiding " + (parts.isEmpty ? last : parts.joined(separator: ", ") + " and " + last)
    }
}
