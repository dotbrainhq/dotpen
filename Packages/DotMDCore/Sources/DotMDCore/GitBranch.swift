import Foundation

/// Reads the checked-out branch from .git/HEAD without running git.
public enum GitBranch {
    /// The branch name, the first 7 characters of the commit when HEAD is detached, or nil outside a repository.
    public static func current(in root: URL) -> String? {
        var gitDirectory = root.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitDirectory.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue {
            // Worktrees and submodules keep a ".git" file that points at the real git folder.
            guard let pointer = try? String(contentsOf: gitDirectory, encoding: .utf8),
                  let line = pointer.split(whereSeparator: \.isNewline).first, line.hasPrefix("gitdir:") else { return nil }
            let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDirectory = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appending(path: path).standardizedFileURL
        }
        guard let head = try? String(contentsOf: gitDirectory.appending(path: "HEAD"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty else { return nil }
        if head.hasPrefix("ref: refs/heads/") { return String(head.dropFirst("ref: refs/heads/".count)) }
        return String(head.prefix(7))
    }
}
