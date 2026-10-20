import Foundation

public enum FileSortOrder: String, CaseIterable, Sendable {
    case lastChanged, name
}

/// What the filter bar asks for.
public struct FileFilter: Equatable, Sendable {
    public var query = ""
    public var unreadOnly = false
    public var changedOnly = false

    public init() {}

    public var isActive: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || unreadOnly || changedOnly
    }
}

/// A folder inside a watched folder and its documents. The folder root has an empty path.
public struct FileGroup: Identifiable, Equatable, Sendable {
    public var path: String
    public var documents: [Document]
    public var id: String { path }
}

/// Turns a folder's documents into the rows the file list shows.
public enum FileTree {
    /// One group per subfolder that holds Markdown, sorted by path, then the files at the root.
    /// Pinned files lead each group.
    public static func groups(for documents: [Document], sort: FileSortOrder, filter: FileFilter) -> [FileGroup] {
        var byDirectory: [String: [Document]] = [:]
        for document in documents where matches(document, filter) {
            byDirectory[document.directory, default: []].append(document)
        }
        let directories = byDirectory.keys.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var groups = directories.map { FileGroup(path: $0, documents: sorted(byDirectory[$0] ?? [], by: sort)) }
        if let root = byDirectory[""] {
            groups.append(FileGroup(path: "", documents: sorted(root, by: sort)))
        }
        guard sort == .lastChanged else { return groups }
        // Sorted by last change, the group holding the newest file comes first, the root files included.
        // The stable sort keeps the name order (subfolders, then root files) for groups that tie.
        let newest = groups.map { $0.documents.map(\.modifiedAt).max() ?? .distantPast }
        return groups.indices.sorted { newest[$0] != newest[$1] ? newest[$0] > newest[$1] : $0 < $1 }.map { groups[$0] }
    }

    static func sorted(_ documents: [Document], by order: FileSortOrder) -> [Document] {
        documents.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if order == .lastChanged, a.modifiedAt != b.modifiedAt { return a.modifiedAt > b.modifiedAt }
            return a.fileName.localizedStandardCompare(b.fileName) == .orderedAscending
        }
    }

    static func matches(_ document: Document, _ filter: FileFilter) -> Bool {
        if filter.changedOnly && document.readState != .changed { return false }
        if filter.unreadOnly && document.readState == .read { return false }
        let query = filter.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return document.relativePath.localizedCaseInsensitiveContains(query)
            || (document.title?.localizedCaseInsensitiveContains(query) ?? false)
    }
}
