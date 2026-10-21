import AppKit
import DotMDCore
import DotMDRender
import SwiftUI

struct ReaderScreen: View {
    let fileURL: URL?
    /// Opens a relative .md link. Without one, the link opens in a new window.
    let onOpenDocument: ((URL) -> ())?

    @Environment(Library.self) private var library
    @State private var controller = ReaderController()
    @State private var text: String
    @AppStorage("readingOptions") private var options = ReadingOptions()
    @State private var showingReadingOptions = false
    @State private var documentKey: Int64?
    /// What changed since the person last read the file, as marked on the page now.
    @State private var changes = ChangeSet()
    /// The line at the top of the view, saved once scrolling settles.
    @State private var scrolledLine: Int?
    /// The previous visit's reading line is shown once, when the file opens, before this visit moves it.
    @State private var memoryShown = false
    /// The start line of the last block written while the file was open, for the caret.
    @State private var lastWrittenLine: Int?

    init(text: String, fileURL: URL?, onOpenDocument: ((URL) -> ())? = nil) {
        self.fileURL = fileURL
        self.onOpenDocument = onOpenDocument
        _text = State(initialValue: text)
    }

    @Environment(\.filesChrome) private var filesChrome

    var body: some View {
        chrome
            // Names the window in the Window menu and Mission Control.
            .navigationTitle(displayTitle)
            .focusedSceneValue(\.documentExporter, exporter)
            .preferredColorScheme(windowScheme)
            .onAppear(perform: start)
            .task(id: fileURL) { await watch() }
            .onChange(of: options) { _, newValue in
                controller.send(.setReadingOptions(newValue))
            }
            .onChange(of: layout) { _, newValue in
                controller.send(.setLayout(newValue))
            }
            .onChange(of: folderSignature, initial: true) { _, _ in
                resolveDocument()
            }
            .onChange(of: assetRoot) { _, root in
                // A window opened before the library loaded starts with the file's own folder as its image root.
                controller.setDocumentLocation(fileURL, root: root)
                controller.send(.render(markdown: text, options: options))
            }
            .onChange(of: readState, initial: true) { _, state in
                markReadIfNeeded(state)
            }
            .onChange(of: isBeingWritten) { _, writing in
                controller.send(.setWriting(writing, lastLine: lastWrittenLine))
            }
            .task(id: scrolledLine) {
                // Saves a second after scrolling stops, not on every pause.
                guard let line = scrolledLine else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let document = libraryDocument else { return }
                library.setReadLine(document, line: line)
            }
            .onChange(of: documentKey, initial: true) { _, _ in
                showMemoryOnce()
            }
    }

    /// In the Files window the reader draws the prototype's own bar; a document window keeps the system toolbar.
    @ViewBuilder private var chrome: some View {
        if let filesChrome {
            VStack(spacing: 0) {
                TopBar(chrome: filesChrome, title: displayTitle, path: displayPath) {
                    Cap { readingOptionsButton.buttonStyle(CapButtonStyle()) }
                    Cap {
                        // The prototype's share button is the icon alone; the label stays for VoiceOver.
                        ShareMenu(exporter: exporter, fileURL: fileURL, markdown: text)
                            .labelStyle(.iconOnly)
                            .menuStyle(.button)
                            .buttonStyle(CapButtonStyle())
                            .fixedSize()
                    }
                }
                ReaderView(controller: controller)
            }
        } else {
            ReaderView(controller: controller)
                .toolbar(removing: .title)
                .toolbar {
                    titleItem
                    ToolbarItemGroup(placement: .primaryAction) {
                        readingOptionsButton
                        ShareMenu(exporter: exporter, fileURL: fileURL, markdown: text)
                    }
                }
        }
    }

    private var readingOptionsButton: some View {
        Button {
            showingReadingOptions.toggle()
        } label: {
            // The prototype's `.aa-btn`: New York at 13 points semibold, tracked slightly tight.
            Text("Aa")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .tracking(-0.26)
        }
        .help("Text size, font and width")
        .accessibilityLabel("Reading options")
        .popover(isPresented: $showingReadingOptions, arrowEdge: .bottom) {
            ReadingOptionsPopover(options: $options)
        }
    }

    /// The title block in a document window's toolbar. On macOS 26 it sits on the toolbar rather than a glass capsule.
    @ToolbarContentBuilder private var titleItem: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .principal) {
                TitleBlock(title: displayTitle, path: displayPath)
                    .frame(maxWidth: 480)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) {
                TitleBlock(title: displayTitle, path: displayPath)
                    .frame(maxWidth: 480)
            }
        }
    }

    private var libraryDocument: DotMDCore.Document? {
        documentKey.flatMap { library.document(key: $0) }
    }

    /// The document's own title, else its file name.
    private var displayTitle: String {
        libraryDocument?.title ?? fileURL?.lastPathComponent ?? "Untitled"
    }

    /// "api-gateway/docs/plans/rate-limiter.md" for a library file; the parent folder and file name otherwise.
    private var displayPath: String {
        if let document = libraryDocument, let folder = library.folders.first(where: { $0.id == document.folderID }) {
            return folder.folder.name + "/" + document.relativePath
        }
        guard let fileURL else { return "" }
        return fileURL.deletingLastPathComponent().lastPathComponent + "/" + fileURL.lastPathComponent
    }

    private var exporter: DocumentExporter {
        DocumentExporter(controller: controller, title: fileURL?.lastPathComponent ?? "Untitled", options: options)
    }

    /// The window follows the page: Night is dark, White and Paper are light, Auto follows the system.
    private var windowScheme: ColorScheme? {
        switch options.paper {
        case .night: .dark
        case .white, .paper: .light
        case .auto: nil
        }
    }

    /// The file's read state in the library, found by the cached key once the file has been matched.
    private var readState: ReadState? {
        documentKey.flatMap { library.document(key: $0)?.readState }
    }

    /// What can make an unmatched file match: a folder connecting or its file list growing.
    private var folderSignature: [String] {
        library.folders.map { "\($0.id) \($0.url?.path ?? "") \($0.documents.count)" }
    }

    /// Matches the file to a library document by path, the costly step. Runs only while the key is unknown or stale.
    private func resolveDocument() {
        if let documentKey, library.document(key: documentKey) == nil {
            // The row was deleted or recreated under a new key.
            self.documentKey = nil
        }
        guard documentKey == nil, let fileURL, let document = library.document(at: fileURL) else { return }
        documentKey = document.key
    }

    /// A new file is read once it's open. A changed file stays changed, with its marks, until Mark read.
    private func markReadIfNeeded(_ state: ReadState?) {
        guard let state, let documentKey, let document = library.document(key: documentKey) else { return }
        switch state {
        case .new:
            library.markRead(document, text: text)
        case .changed:
            Task { await refreshMarks() }
        case .read:
            guard !changes.isEmpty else { return }
            changes = ChangeSet()
            controller.send(.clearMarks(fade: true))
        }
    }

    /// Diffs the file against the text last read and marks the page. A changed file with nothing to show, because
    /// True while an agent is writing the file (M2's heuristic until M5 knows the session).
    private var isBeingWritten: Bool {
        documentKey.map { library.writing.contains($0) } ?? false
    }

    /// DotMD has no copy of what was read or only front matter changed, is marked read instead.
    private func refreshMarks() async {
        guard let document = libraryDocument, document.readState == .changed else { return }
        guard let old = library.lastReadText(for: document) else {
            library.markRead(document, text: text)
            return
        }
        let current = text
        let result = await Task.detached { ChangeDiff.changes(from: old, to: current) }.value
        // A reload that landed meanwhile starts its own diff.
        guard !Task.isCancelled, current == text else { return }
        if result.isEmpty {
            library.markRead(document, text: current)
            return
        }
        changes = result
        controller.send(.applyMarks(changes: result, since: ReadingLabels.since(document.lastReadAt)))
    }

    /// Shows where reading stopped last time, once per visit. Nothing shows when it stopped at the top.
    private func showMemoryOnce() {
        guard !memoryShown, let document = libraryDocument else { return }
        memoryShown = true
        guard let line = document.readLine, line > 1, let at = document.readLineAt else { return }
        controller.send(.setMemory(line: line, label: ReadingLabels.stoppedReading(at: at)))
    }

    /// The watched folder holding this file: relative images may come from anywhere inside it.
    private var assetRoot: URL? {
        fileURL.flatMap { library.folder(containing: $0)?.url }
    }

    /// The Files window with its list showing uses the files layout; a hidden list or a document window, the document one.
    private var layout: ReaderLayout {
        filesChrome?.sidebarVisible == true ? .files : .document
    }

    private func start() {
        controller.onMessage = handle
        controller.setDocumentLocation(fileURL, root: assetRoot)
        controller.send(.setLayout(layout))
        controller.send(.render(markdown: text, options: options))
    }

    /// Runs for as long as the window is open. SwiftUI cancels the task on close, which ends the loop and the observer.
    private func watch() async {
        guard let fileURL else { return }
        let (changes, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        let observer = FileObserver(url: fileURL) { continuation.yield(true) }
        defer {
            observer.cancel()
            continuation.finish()
        }
        for await _ in changes {
            await reload(from: fileURL)
        }
    }

    private func reload(from url: URL) async {
        let data = await Task.detached { try? Data(contentsOf: url) }.value
        guard let data, !Task.isCancelled else { return }
        let newText = String(decoding: data, as: UTF8.self)
        guard newText != text else { return }
        let previous = text
        text = newText
        controller.send(.render(markdown: newText, options: options))
        // What just changed glows, whatever the person has read.
        let written = await Task.detached { ChangeDiff.changes(from: previous, to: newText) }.value
        let lines = (written.added.map(\.start) + written.changed.map(\.start)).sorted()
        if !lines.isEmpty {
            lastWrittenLine = lines.last
            controller.send(.markLive(lines: lines))
            controller.send(.setWriting(isBeingWritten, lastLine: lastWrittenLine))
        }
        await refreshMarks()
    }

    private func handle(_ message: ReaderMessage) {
        switch message {
        case let .linkActivated(href):
            if let local = localMarkdownURL(href) {
                if let onOpenDocument { onOpenDocument(local) } else { FileActions.openInNewWindow(local) }
                return
            }
            guard let url = URL(string: href), let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else { return }
            NSWorkspace.shared.open(url)
        case let .copyText(value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        case .markRead:
            guard let document = libraryDocument else { return }
            library.markRead(document, text: text)
        case let .scrollLine(line):
            scrolledLine = line
        default:
            break
        }
    }

    /// A link like "../specs/api.md" or "/docs/plan.md#steps", resolved against this file. Nil for anything else.
    private func localMarkdownURL(_ href: String) -> URL? {
        guard let fileURL, URL(string: href)?.scheme == nil else { return nil }
        let raw = String(href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let path = raw.removingPercentEncoding ?? raw
        guard ["md", "markdown", "mdown"].contains((path as NSString).pathExtension.lowercased()) else { return nil }
        let base = path.hasPrefix("/")
            ? (assetRoot ?? fileURL.deletingLastPathComponent())
            : fileURL.deletingLastPathComponent()
        return base.appending(path: String(path.drop { $0 == "/" })).standardizedFileURL
    }
}
