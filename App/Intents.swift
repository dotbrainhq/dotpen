import AppIntents
import DotPenCore
import Foundation

/// A Markdown file in a watched folder, as Shortcuts shows and picks it.
struct MarkdownFileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Markdown File"
    static let defaultQuery = MarkdownFileQuery()

    /// The document's key. App Intents identifiers are Int, not Int64.
    let id: Int
    let title: String
    let path: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(path)")
    }

    @MainActor
    init(_ document: DotPenCore.Document, folder: String) {
        id = Int(document.key)
        title = document.title ?? (document.relativePath as NSString).lastPathComponent
        path = "\(folder)/\(document.relativePath)"
    }
}

struct MarkdownFileQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [MarkdownFileEntity] {
        await AppServices.start()
        return await Self.all().filter { identifiers.contains($0.id) }
    }

    /// Unread files first, then the rest by when they last changed.
    func suggestedEntities() async throws -> [MarkdownFileEntity] {
        await AppServices.start()
        return await Array(Self.all().prefix(30))
    }

    func entities(matching string: String) async throws -> [MarkdownFileEntity] {
        await AppServices.start()
        return await Self.all()
            .compactMap { entity in FuzzyMatch.score(string, in: entity.title + " " + entity.path).map { (entity, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    @MainActor
    static func all() -> [MarkdownFileEntity] {
        AppServices.library.folders
            .flatMap { folder in folder.documents.map { ($0, folder.folder.name) } }
            .sorted { ($0.0.readState != .read ? 1 : 0, $0.0.modifiedAt) > ($1.0.readState != .read ? 1 : 0, $1.0.modifiedAt) }
            .map { MarkdownFileEntity($0.0, folder: $0.1) }
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case fileNotFound

    var localizedStringResource: LocalizedStringResource {
        "dotPen can't find that file in its watched folders."
    }
}

@MainActor
private func document(_ entity: MarkdownFileEntity) async throws -> (DotPenCore.Document, URL, String) {
    await AppServices.start()
    let library = AppServices.library
    guard let document = library.document(key: Int64(entity.id)), let url = library.url(for: document) else { throw IntentError.fileNotFound }
    let text = await Task.detached { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }.value
    return (document, url, text)
}

/// Opens a file in a dotPen window.
struct OpenFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Open File"
    static let description = IntentDescription("Opens a Markdown file from dotPen's watched folders.")
    static let openAppWhenRun = true

    @Parameter(title: "File") var file: MarkdownFileEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let (_, url, _) = try await document(file)
        FileActions.openInNewWindow(url)
        return .result()
    }
}

/// What changed in a file since you last read it, one line per change, as Send's change notes put it.
struct ChangesSinceReadIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Changes Since Last Read"
    static let description = IntentDescription("Lists what changed in a Markdown file since you last read it in dotPen.")

    @Parameter(title: "File") var file: MarkdownFileEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let (document, _, text) = try await document(file)
        guard document.readState == .changed, let old = AppServices.library.lastReadText(for: document) else {
            return .result(value: [])
        }
        let changes = await Task.detached { ChangeDiff.changes(from: old, to: text) }.value
        return .result(value: PromptBuilder.changeNotes(changes, in: text))
    }
}

/// Every unticked task in the watched folders, with the file it's in.
struct ListOpenTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "List Open Tasks"
    static let description = IntentDescription("Lists the unticked tasks in every Markdown file dotPen watches.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        await AppServices.start()
        let library = AppServices.library
        let files = library.folders.flatMap { folder in
            folder.documents.compactMap { document in library.url(for: document).map { ($0, "\(folder.folder.name)/\(document.relativePath)") } }
        }
        let tasks = await Task.detached {
            files.flatMap { url, path in
                OpenTasks.find(in: (try? String(contentsOf: url, encoding: .utf8)) ?? "").map { "\($0) (\(path))" }
            }
        }.value
        return .result(value: tasks)
    }
}

/// The prompt for a file's comments that haven't gone out yet. Running it marks them sent, as Send does.
struct SendCommentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Comments to Agent"
    static let description = IntentDescription("Builds the prompt from a file's open comments and marks them sent. Pass it to your agent.")

    @Parameter(title: "File") var file: MarkdownFileEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (document, _, text) = try await document(file)
        let library = AppServices.library
        let waiting = library.comments(for: document, text: text).filter(\.comment.isInPrompt)
        guard !waiting.isEmpty else { return .result(value: "") }
        let items = waiting.map { item in
            PromptBuilder.Item(lineStart: item.range?.start ?? item.comment.lineStart, lineEnd: item.range?.end ?? item.comment.lineEnd,
                               quote: item.comment.quote, body: item.comment.body)
        }
        let prompt = PromptBuilder.prompt(path: document.relativePath, noun: document.kind.promptNoun, items: items)
        library.markSent(waiting.map(\.comment), resolve: false)
        return .result(value: prompt)
    }
}

struct DotPenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenFileIntent(), phrases: ["Open a file in \(.applicationName)"],
                    shortTitle: "Open File", systemImageName: "doc.text")
        AppShortcut(intent: ChangesSinceReadIntent(), phrases: ["Show changes in \(.applicationName)"],
                    shortTitle: "Changes Since Last Read", systemImageName: "clock.arrow.circlepath")
        AppShortcut(intent: ListOpenTasksIntent(), phrases: ["List open tasks in \(.applicationName)"],
                    shortTitle: "Open Tasks", systemImageName: "checklist")
        AppShortcut(intent: SendCommentsIntent(), phrases: ["Send comments with \(.applicationName)"],
                    shortTitle: "Send Comments", systemImageName: "paperplane")
    }
}
