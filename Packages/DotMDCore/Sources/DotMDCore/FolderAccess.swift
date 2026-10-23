import Foundation

public enum FolderAccessError: Error {
    case accessDenied
}

/// Security-scoped bookmarks: the only way a sandboxed DotMD keeps a folder the person chose.
public enum FolderAccess {
    public struct Resolved: Sendable {
        public let url: URL
        /// A new bookmark when the old one went stale because the folder moved. Store it in place of the old one.
        public let refreshedBookmark: Data?
    }

    public static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a bookmark and starts security-scoped access. Call stop(_:) when the folder is no longer watched.
    public static func resolve(_ bookmark: Data) throws -> Resolved {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.startAccessingSecurityScopedResource() else { throw FolderAccessError.accessDenied }
        return Resolved(url: url, refreshedBookmark: stale ? try? Self.bookmark(for: url) : nil)
    }

    public static func stop(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    /// A folder moved to the Trash was deleted as far as the person is concerned, though its bookmark still finds it.
    public static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    /// The real path with symlinks resolved, in the form FSEvents reports. See Paths.canonical.
    public static func canonical(_ url: URL) -> URL {
        Paths.canonical(url)
    }
}
