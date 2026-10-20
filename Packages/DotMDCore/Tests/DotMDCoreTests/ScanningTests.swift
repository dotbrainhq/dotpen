import Foundation
import Testing
@testable import DotMDCore

@Test func builtInFoldersAreIgnoredAnywhere() {
    let rules = IgnoreRules()
    #expect(rules.isIgnored("node_modules", isDirectory: true))
    #expect(rules.isIgnored("web/node_modules", isDirectory: true))
    #expect(rules.isIgnored(".git", isDirectory: true))
    #expect(!rules.isIgnored("build.md", isDirectory: false))
    #expect(!rules.isIgnored("docs", isDirectory: true))
}

@Test func gitignorePatterns() {
    let rules = IgnoreRules(gitignore: """
    # comment
    *.log
    out/
    /secret.md
    docs/private
    **/tmp
    drafts/**
    !keep.md
    """)
    #expect(rules.isIgnored("debug.log", isDirectory: false))
    #expect(rules.isIgnored("logs/debug.log", isDirectory: false))
    #expect(rules.isIgnored("out", isDirectory: true))
    #expect(!rules.isIgnored("out", isDirectory: false))
    #expect(rules.isIgnored("secret.md", isDirectory: false))
    #expect(!rules.isIgnored("docs/secret.md", isDirectory: false))
    #expect(rules.isIgnored("docs/private", isDirectory: true))
    #expect(rules.isIgnored("a/b/tmp", isDirectory: true))
    #expect(rules.isIgnored("drafts", isDirectory: true))
    #expect(!rules.isIgnored("notes/drafts", isDirectory: true))
    #expect(!rules.isIgnored("keep.md", isDirectory: false))
}

@Test func eventPathsInsideIgnoredFoldersAreIgnored() {
    let rules = IgnoreRules(gitignore: "out/")
    #expect(rules.containsIgnoredPath("node_modules/pkg/README.md"))
    #expect(rules.containsIgnoredPath("out/report.md"))
    #expect(!rules.containsIgnoredPath("docs/out.md"))
}

@Test func noneHidesNothing() {
    #expect(!IgnoreRules.none.isIgnored("node_modules", isDirectory: true))
}

@Test func scanFindsMarkdownAndSkipsIgnoredPaths() throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("docs/specs/token-bucket.markdown", "# Token bucket")
    try temp.write("docs/notes.txt", "not markdown")
    try temp.write("node_modules/pkg/README.md", "# Dependency")
    try temp.write("out/report.md", "# Report")
    try temp.write(".gitignore", "out/\n")
    let result = FolderScanner.scan(root: temp.url, rules: .load(root: temp.url))
    #expect(result.files.map(\.relativePath) == ["README.md", "docs/specs/token-bucket.markdown"])
    #expect(result.files.map(\.title) == ["Repo", "Token bucket"])
    #expect(result.files.map(\.kind) == [.readme, .spec])
    #expect(Set(result.ignored) == ["node_modules", "out"])
}

@Test func showingIgnoredPathsFindsEverything() throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("node_modules/pkg/README.md", "# Dependency")
    let result = FolderScanner.scan(root: temp.url, rules: .none)
    #expect(result.files.map(\.relativePath) == ["README.md", "node_modules/pkg/README.md"])
    #expect(result.ignored.isEmpty)
}

@Test func hashesFollowContent() throws {
    let temp = try TempFolder()
    let a = try temp.write("a.md", "# Same")
    let b = try temp.write("b.md", "# Same")
    let c = try temp.write("c.md", "# Different")
    let hash = { (url: URL) in FolderScanner.summarize(fileURL: url, relativePath: url.lastPathComponent)?.contentHash }
    #expect(hash(a) == hash(b))
    #expect(hash(a) != hash(c))
}

@Test func countingSkipsIgnoredFiles() throws {
    let temp = try TempFolder()
    try temp.write("README.md", "# Repo")
    try temp.write("node_modules/pkg/README.md", "# Dependency")
    #expect(FolderScanner.countMarkdown(root: temp.url, rules: .load(root: temp.url)) == 1)
}

@Test func branchComesFromHEAD() throws {
    let temp = try TempFolder()
    #expect(GitBranch.current(in: temp.url) == nil)
    try temp.write(".git/HEAD", "ref: refs/heads/feat/rate-limit\n")
    #expect(GitBranch.current(in: temp.url) == "feat/rate-limit")
    try temp.write(".git/HEAD", "9fceb02d0ae598e95dc970b74767f19372d61af8\n")
    #expect(GitBranch.current(in: temp.url) == "9fceb02")
}

@Test func worktreesPointAtTheirGitFolder() throws {
    let temp = try TempFolder()
    try temp.write("main/.git/worktrees/feature/HEAD", "ref: refs/heads/feature\n")
    try temp.write("feature/.git", "gitdir: ../main/.git/worktrees/feature\n")
    #expect(GitBranch.current(in: temp.url.appending(path: "feature")) == "feature")
}

@Test func doubleStarMatchesAnyNumberOfFolders() {
    let rules = IgnoreRules(gitignore: "**/foo/bar\na/**/b\n")
    #expect(rules.isIgnored("foo/bar", isDirectory: true))
    #expect(rules.isIgnored("x/y/foo/bar", isDirectory: true))
    #expect(rules.isIgnored("a/b", isDirectory: true))
    #expect(rules.isIgnored("a/x/b", isDirectory: true))
    #expect(rules.isIgnored("a/x/y/b", isDirectory: true))
    #expect(!rules.isIgnored("c/a/b", isDirectory: true))
}

@Test func scanningThroughASymlinkedRootWorks() throws {
    let target = try TempFolder()
    try target.write("README.md", "# Repo")
    let holder = try TempFolder()
    let link = holder.url.appending(path: "link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target.url)
    let result = FolderScanner.scan(root: link, rules: .none)
    #expect(result.files.map(\.relativePath) == ["README.md"])
    #expect(FolderScanner.countMarkdown(root: link, rules: .none) == 1)
}

@Test func ignoredListSkipsFilesThatAreNotMarkdown() throws {
    let temp = try TempFolder()
    try temp.write("debug.log", "noise")
    try temp.write("out/report.md", "# Report")
    let result = FolderScanner.scan(root: temp.url, rules: IgnoreRules(gitignore: "*.log\nout/\n"))
    #expect(!result.ignored.contains("debug.log"))
    #expect(result.ignored.contains("out"))
}

@Test func eventPathNamingAnIgnoredFolderIsIgnored() {
    #expect(IgnoreRules().containsIgnoredPath("node_modules"))
}

@Test func nonBranchRefsKeepTheirName() throws {
    let temp = try TempFolder()
    try temp.write(".git/HEAD", "ref: refs/remotes/origin/main\n")
    #expect(GitBranch.current(in: temp.url) == "remotes/origin/main")
}

@Test func uppercaseMarkdownExtensionIsFound() throws {
    let temp = try TempFolder()
    try temp.write("NOTES.MD", "# Notes")
    let result = FolderScanner.scan(root: temp.url, rules: .none)
    #expect(result.files.map(\.relativePath) == ["NOTES.MD"])
}
