import AppKit
import CryptoKit
import DotPenBridge
import DotPenCore
import DotPenRender
import SwiftUI

struct ReaderScreen: View {
    let fileURL: URL?
    /// Opens a relative .md link. Without one, the link opens in a new window.
    let onOpenDocument: ((URL) -> ())?
    /// Close on the deleted-file notice. A document window closes itself instead.
    let onClose: (() -> ())?
    /// J and K: the next or previous file in the Files window's list. A document window has no list.
    let onStepFile: ((Int) -> ())?
    /// Reached by J or K: the page takes the keyboard once drawn, so the next J or K works from it too.
    let takesFocus: Bool

    @Environment(Library.self) private var library
    @Environment(AgentBridge.self) private var bridge
    @Environment(AgentActivity.self) private var activity
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
    /// The file's comments, each with where its passage is now.
    @State private var comments: [PlacedComment] = []
    @State private var showingComments = false
    /// The Send sheet in a document window. The Files window shows it over the whole window instead.
    @State private var showingSend = false
    /// A comment composer on the page has focus, so ⌘↩ saves the comment rather than opening Send.
    @State private var composing = false
    /// While an agent writes the file, the view keeps its newest block in sight. Stop following turns that off.
    @State private var following = true
    /// The agent that just stopped writing this file, for the finished pill, until it's dismissed.
    @State private var finishedBy: String?
    /// The palette or the shortcuts in a document window. The Files window keeps its own.
    @State private var overlay: WindowOverlay?
    /// The file's headings, for the palette.
    @State private var headings: [DocumentHeading] = []
    /// The file went away: the reader keeps its last version, faded, under a notice.
    @State private var fileGone = false
    /// The library's record of the file, kept so the title bar still names it after the file goes.
    @State private var lastLibraryDocument: DotPenCore.Document?
    /// When the reader last read the file from disk, for the deleted-file notice.
    @State private var readFromDiskAt = Date.now
    /// Show All on the large-file notice.
    @State private var showAll = false
    /// Show Source (⌘U): the file as written instead of the page.
    @State private var showingSource = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(text: String, fileURL: URL?, onOpenDocument: ((URL) -> ())? = nil, onClose: (() -> ())? = nil,
         onStepFile: ((Int) -> ())? = nil, takesFocus: Bool = false) {
        self.fileURL = fileURL
        self.onOpenDocument = onOpenDocument
        self.onClose = onClose
        self.onStepFile = onStepFile
        self.takesFocus = takesFocus
        _text = State(initialValue: text)
    }

    @Environment(\.filesChrome) private var filesChrome

    var body: some View {
        chrome
            // Names the window in the Window menu and Mission Control.
            .navigationTitle(displayTitle)
            // Export draws the page, so it waits while the source shows.
            .focusedSceneValue(\.documentExporter, showingSource ? nil : exporter)
            .focusedSceneValue(\.readerCommands, readerCommands)
            .task(id: text) {
                let current = text
                headings = await Task.detached { DocumentHeadings.headings(in: current) }.value
            }
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
                controller.send(.render(markdown: shownMarkdown, options: options, format: SourceFormat(url: fileURL)))
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
            .task(id: CommentsKey(version: library.commentsVersion, document: documentKey, text: text)) {
                loadComments()
            }
            .onChange(of: showingComments) { _, open in
                controller.send(.setPanel(open))
            }
            .onChange(of: notice, initial: true) { _, notice in
                controller.send(.setNotice(notice))
            }
            .onChange(of: libraryDocument, initial: true) { _, document in
                if let document { lastLibraryDocument = document }
            }
            .onChange(of: showAll) {
                controller.send(.render(markdown: shownMarkdown, options: options, format: SourceFormat(url: fileURL)))
            }
            .onChange(of: showingSource) { _, on in
                controller.send(.setSource(on))
            }
            .onChange(of: writingAgent) { previous, agent in
                if let agent {
                    finishedBy = nil
                    if previous == nil { following = true }
                } else if let previous {
                    finishedBy = previous
                }
            }
    }

    /// In the Files window the reader draws the prototype's own bar; a document window keeps the system toolbar.
    @ViewBuilder private var chrome: some View {
        if let filesChrome {
            VStack(spacing: 0) {
                TopBar(chrome: filesChrome, title: displayTitle, path: displayPath) {
                    Cap { readingOptionsButton.buttonStyle(CapButtonStyle()) }
                    Cap {
                        commentsButton.buttonStyle(CapButtonStyle())
                        // The prototype's share button is the icon alone; the label stays for VoiceOver.
                        ShareMenu(exporter: exporter, canExport: !showingSource, fileURL: fileURL, markdown: text)
                            .labelStyle(.iconOnly)
                            .menuStyle(.button)
                            .buttonStyle(CapButtonStyle())
                            .fixedSize()
                    }
                    Cap { sendButton.buttonStyle(CapButtonStyle(tint: Palette.accentInk, weight: .semibold)) }
                }
                reader
            }
        } else {
            reader
                .overlay(alignment: .top) {
                    if showingSend {
                        ZStack(alignment: .top) {
                            Palette.scrim
                                .contentShape(Rectangle())
                                .onTapGesture(perform: closeSend)
                            sendSheet
                        }
                        .transition(.opacity)
                    }
                }
                .windowOverlays($overlay) { document, _ in
                    if let url = library.url(for: document) { FileActions.openInNewWindow(url) }
                }
                .focusedSceneValue(\.showOverlay) { overlay = $0 }
                .toolbar(removing: .title)
                .toolbar {
                    titleItem
                    ToolbarItemGroup(placement: .primaryAction) {
                        readingOptionsButton
                        commentsButton
                        ShareMenu(exporter: exporter, canExport: !showingSource, fileURL: fileURL, markdown: text)
                        sendButton
                    }
                }
        }
    }

    /// The reader with what sits on it: the arrival banner above, an agent pill at the bottom, the panel on the right.
    private var reader: some View {
        VStack(spacing: 0) {
            if let arrival = shownArrival {
                ArrivalBanner(
                    agent: arrival.agent.name,
                    file: URL(fileURLWithPath: arrival.path).lastPathComponent,
                    folder: library.folder(containing: URL(fileURLWithPath: arrival.path))?.folder.name ?? "",
                    onOpen: {
                        let url = URL(fileURLWithPath: arrival.path)
                        activity.dismissArrival()
                        if let onOpenDocument { onOpenDocument(url) } else { FileActions.openInNewWindow(url) }
                    },
                    onDismiss: activity.dismissArrival
                )
                .transition(.opacity)
            }
            ReaderView(controller: controller)
                .overlay(alignment: .bottom) { agentPill }
        }
        .overlay(alignment: .trailing) { panel }
    }

    /// What this reader offers the palette and the menus.
    private var readerCommands: ReaderCommands {
        var markRead: (() -> ())?
        if let document = libraryDocument, document.readState != .read {
            let current = text
            markRead = { library.markRead(document, text: current) }
        }
        var send: (() -> ())?
        var copyPrompt: (() -> ())?
        if !inPrompt.isEmpty {
            send = openSend
            // Built when used: the prompt parses the file for its change notes.
            copyPrompt = { copy(prompt(includeChanges: true)) }
        }
        let exporter = exporter
        return ReaderCommands(
            headings: headings,
            reveal: { line in controller.send(.reveal(line: line)) },
            send: send,
            markRead: markRead,
            copyPrompt: copyPrompt,
            exportPDF: showingSource ? nil : { exporter.export(as: .pdf) },
            print: showingSource ? nil : { exporter.print() },
            copyMarkdown: { exporter.copyMarkdown() },
            showingSource: showingSource,
            toggleSource: { showingSource.toggle() }
        )
    }

    // MARK: Edge states

    /// Past 1 MB the reader shows the first 2,000 lines, as the spec asks, until Show All.
    private static let largeFileBytes = 1_000_000
    private static let largeFileLines = 2_000

    private var isLarge: Bool { text.utf8.count > Self.largeFileBytes }

    private var shownMarkdown: String {
        guard isLarge, !showAll else { return text }
        var newlines = 0
        for index in text.indices where text[index] == "\n" {
            newlines += 1
            if newlines == Self.largeFileLines { return String(text[..<index]) }
        }
        return text
    }

    /// The prototype's notices above the page: a file that went away, then a large file shown in part.
    private var notice: PageNotice? {
        if fileGone {
            return PageNotice(
                icon: "trash",
                title: "\(fileURL?.lastPathComponent ?? "This file") has gone missing.",
                text: "You're reading the copy from \(readFromDiskAt.formatted(date: .omitted, time: .shortened)).",
                buttons: [PageNotice.Button(id: "find", label: "Find It"), PageNotice.Button(id: "close", label: "Close", quiet: true)],
                dim: true
            )
        }
        if let documentKey, let review = AppServices.reviews.pending(for: documentKey) {
            return PageNotice(
                icon: "review",
                title: "\(review.agent ?? "Your agent") asked for your review.",
                text: review.note.map { "\u{201C}\($0)\u{201D}" } ?? "Comment on anything you'd change. It waits until you're done.",
                buttons: [PageNotice.Button(id: "reviewDone", label: "Done Reviewing")]
            )
        }
        if isLarge, !showAll {
            let size = ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file)
            return PageNotice(
                icon: "gauge",
                title: "This one's big, \(size).",
                text: "dotPen shows the first 2,000 lines so it stays quick.",
                buttons: [PageNotice.Button(id: "showAll", label: "Show All")]
            )
        }
        return nil
    }

    /// Find It: a watched file with the same content is this one moved; otherwise the person points at it.
    private func findMovedFile() {
        let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        let moved = library.folders.lazy.flatMap(\.documents).first { $0.contentHash == hash }
        if let moved, let url = library.url(for: moved) {
            if let onOpenDocument { onOpenDocument(url) } else { FileActions.openInNewWindow(url) }
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.markdown]
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        panel.message = "Find where \(fileURL?.lastPathComponent ?? "the file") went."
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let onOpenDocument { onOpenDocument(url) } else { FileActions.openInNewWindow(url) }
    }

    // MARK: Agents

    /// The agent writing this file right now, by name, when its session log says so.
    private var writingAgent: String? {
        fileURL.flatMap { activity.writingSession(for: $0) }?.agent.name
    }

    /// Who Send goes to: the agent that last wrote this file, else the last one that connected to the bridge.
    private var agentName: String {
        fileURL.flatMap { activity.writer(for: $0) }?.agent.name ?? bridge.lastAgent ?? "your agent"
    }

    /// "Connected to Claude Code in api-gateway": the bridge is on, and the agent that last connected to it has a
    /// session running in this file's folder.
    private var connectedTo: String? {
        guard case .running = bridge.state, let agent = bridge.lastAgent, let fileURL,
              let folder = library.folder(containing: fileURL), let root = folder.url,
              activity.activeSession(in: root, agent: agent) != nil else { return nil }
        return "Connected to \(agent) in \(folder.folder.name)"
    }

    /// The prototype shows the arrival banner in the document layout only, for a new file other than this one.
    private var shownArrival: AgentWrite? {
        guard layout == .document, finishedBy == nil, !fileGone, let arrival = activity.arrival,
              arrival.path != fileURL.map(AgentActivity.path) else { return nil }
        let document = library.document(at: URL(fileURLWithPath: arrival.path))
        return document.map { $0.readState == .new } ?? true ? arrival : nil
    }

    /// One notice at a time: finished beats the arrival banner, which beats following.
    @ViewBuilder private var agentPill: some View {
        if fileGone {
            // The deleted-file notice comes first; one notice at a time.
            EmptyView()
        } else if let finishedBy {
            FinishedPill(
                agent: finishedBy,
                changes: changes.added.count + changes.changed.count + changes.removed.count,
                onReview: {
                    controller.send(.nextChange)
                    self.finishedBy = nil
                },
                onDismiss: { self.finishedBy = nil }
            )
            .transition(.opacity)
        } else if let writingAgent, shownArrival == nil {
            FollowingPill(agent: writingAgent, following: following, onToggle: toggleFollow)
                .transition(.opacity)
        }
    }

    private func toggleFollow() {
        guard writingAgent != nil else { return }
        following.toggle()
        if following, let lastWrittenLine { controller.send(.follow(line: lastWrittenLine)) }
    }

    // MARK: Comments

    private struct CommentsKey: Equatable {
        let version: Int
        let document: Int64?
        let text: String
    }

    private var commentsButton: some View {
        Button {
            withAnimation(panelAnimation) { showingComments.toggle() }
        } label: {
            Icon("bubble", size: 16)
        }
        .help("Show all comments")
        .accessibilityLabel("Comments")
    }

    /// The prototype's `.cap.send`: green and semibold with the count, ink-4 and still when nothing's waiting.
    private var sendButton: some View {
        Button(action: openSend) {
            HStack(spacing: 6) {
                Icon("send", size: 16)
                Text("Send to agent")
                if inPrompt.count > 0 { CountBadge(count: inPrompt.count) }
            }
        }
        .disabled(inPrompt.isEmpty || showingSend)
        .keyboardShortcut(composing ? nil : KeyboardShortcut(.return, modifiers: .command))
        .help("Send to agent ⌘↩")
    }

    @ViewBuilder private var panel: some View {
        if showingComments {
            CommentsPanel(
                comments: comments,
                agent: agentName,
                onReveal: { item in
                    if let range = item.range { controller.send(.reveal(line: range.start)) }
                },
                onResolve: { comment, resolved in library.setResolved(comment, resolved) },
                onSend: openSend,
                onCopyPrompt: { copy(prompt(includeChanges: true)) }
            )
            .transition(reduceMotion ? .opacity : .move(edge: .trailing))
        }
    }

    private var panelAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)
    }

    /// Open comments the next Send carries, in reading order.
    private var inPrompt: [PlacedComment] {
        comments.filter(\.comment.isInPrompt)
    }

    private var promptItems: [PromptBuilder.Item] {
        inPrompt.map { item in
            PromptBuilder.Item(
                lineStart: item.range?.start ?? item.comment.lineStart,
                lineEnd: item.range?.end ?? item.comment.lineEnd,
                quote: item.comment.quote,
                body: item.comment.body
            )
        }
    }

    private func prompt(includeChanges: Bool) -> String {
        guard let document = libraryDocument else { return "" }
        let notes = includeChanges ? PromptBuilder.changeNotes(changes, in: text) : []
        return PromptBuilder.prompt(path: document.relativePath, noun: document.kind.promptNoun, items: promptItems, changeNotes: notes)
    }

    private var sendSheet: SendSheet {
        let items = inPrompt.map(\.comment)
        return SendSheet(
            agent: agentName,
            connectedTo: connectedTo,
            path: libraryDocument?.relativePath ?? "",
            noun: libraryDocument?.kind.promptNoun ?? "file",
            items: promptItems,
            changeNotes: PromptBuilder.changeNotes(changes, in: text),
            onCopy: { prompt in
                copy(prompt)
                closeSend()
            },
            onSend: { [library] prompt, resolve in
                copy(prompt)
                library.markSent(items, resolve: resolve)
                closeSend()
            },
            onClose: closeSend
        )
    }

    private func openSend() {
        guard !inPrompt.isEmpty else { return }
        let animation: Animation = reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)
        if let filesChrome {
            withAnimation(animation) { filesChrome.showSheet(AnyView(sendSheet)) }
        } else {
            withAnimation(animation) { showingSend = true }
        }
    }

    private func closeSend() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)) {
            filesChrome?.showSheet(nil)
            showingSend = false
        }
    }

    /// Who writes the comments: the person's initial in the avatar, and "You".
    private var author: CommentAuthor {
        CommentAuthor(initial: NSFullUserName().first.map { String($0).uppercased() } ?? "Y", name: "You")
    }

    /// Finds each comment's passage in the text as it is now and shows the open ones beside the text, numbered.
    private func loadComments() {
        guard let document = libraryDocument else {
            comments = []
            controller.send(.setComments([], author: author, canComment: false))
            return
        }
        comments = library.comments(for: document, text: text)
        let shown = comments.filter { $0.comment.status == .open && $0.range != nil }
        let items = shown.enumerated().map { index, item in
            PageComment(
                id: item.comment.key,
                line: item.range?.start ?? item.comment.lineStart,
                quote: item.comment.quote,
                body: item.comment.body,
                when: ReadingLabels.commentTime(item.comment.createdAt),
                inPrompt: item.comment.isInPrompt,
                number: index + 1
            )
        }
        controller.send(.setComments(items, author: author, canComment: true))
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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

    private var libraryDocument: DotPenCore.Document? {
        documentKey.flatMap { library.document(key: $0) }
    }

    private var shownDocument: DotPenCore.Document? {
        libraryDocument ?? (fileGone ? lastLibraryDocument : nil)
    }

    /// The document's own title, else its file name.
    private var displayTitle: String {
        shownDocument?.title ?? fileURL?.lastPathComponent ?? "Untitled"
    }

    /// "api-gateway/docs/plans/rate-limiter.md" for a library file; the parent folder and file name otherwise.
    private var displayPath: String {
        if let document = shownDocument, let folder = library.folders.first(where: { $0.id == document.folderID }) {
            return folder.folder.name + "/" + document.relativePath
        }
        guard let fileURL else { return "" }
        return fileURL.deletingLastPathComponent().lastPathComponent + "/" + fileURL.lastPathComponent
    }

    private var exporter: DocumentExporter {
        DocumentExporter(controller: controller, title: fileURL?.lastPathComponent ?? "Untitled", options: options, markdown: text)
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

    /// True while an agent is writing the file: its session log says so, or, for agents without readable logs, the
    /// file changed in the last few seconds.
    private var isBeingWritten: Bool {
        writingAgent != nil || (documentKey.map { library.writing.contains($0) } ?? false)
    }

    /// Diffs the file against the text last read and marks the page. A changed file with nothing to show, because
    /// dotPen has no copy of what was read or only front matter changed, is marked read instead.
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
        controller.send(.applyMarks(changes: result, since: ReadingLabels.since(library.lastReadDate(for: document))))
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
        controller.send(.setTasksEditable(fileURL.map { FileManager.default.isWritableFile(atPath: $0.path) } ?? false))
        controller.send(.render(markdown: shownMarkdown, options: options, format: SourceFormat(url: fileURL)))
    }

    // MARK: Tasks

    /// A box ticked on the page goes into the file, if the file on disk is still the text on screen. Otherwise the
    /// page draws again from what dotPen has, so the box shows what the file says.
    private func tick(line: Int, checked: Bool) async {
        guard let fileURL else { return }
        let shown = text
        let disk = await Task.detached { try? Data(contentsOf: fileURL) }.value.flatMap { String(data: $0, encoding: .utf8) }
        guard disk == shown, let tick = TaskToggle.toggle(shown, line: line, checked: checked) else {
            refuseTick()
            return
        }
        let content = Data(tick.text.utf8)
        let document = libraryDocument
        if document != nil { library.expectOwnWrite(content) }
        // Set first, so the file watcher finds nothing new to draw or glow.
        text = tick.text
        // In place, not by replacing the file: a file opened on its own gives dotPen no folder to write a new one in.
        let saved = await Task.detached { (try? content.write(to: fileURL)) != nil }.value
        guard saved else {
            text = shown
            refuseTick()
            return
        }
        guard let document else { return }
        // The person's own tick isn't a change to review: the copy last read takes it too.
        if document.readState == .read {
            library.replaceReadText(document, with: tick.text)
        } else if let read = library.lastReadText(for: document),
                  let mirrored = TaskToggle.mirror(read, from: tick.oldLine, to: tick.newLine) {
            library.replaceReadText(document, with: mirrored)
        }
    }

    /// Accept in the review bar: the change goes into the copy dotPen counts as read, so it stops showing. The file
    /// stays as the agent wrote it. The page then moves on to the next change.
    private func acceptChange(kind: String, line: Int) {
        guard let document = libraryDocument, let kind = ChangeKind(rawValue: kind),
              let read = library.lastReadText(for: document),
              let accepted = ChangeDiff.accepting(kind, at: line, from: read, to: text) else {
            NSSound.beep()
            return
        }
        library.replaceReadText(document, with: accepted)
        Task { await refreshMarks() }
    }

    private func refuseTick() {
        NSSound.beep()
        controller.send(.render(markdown: shownMarkdown, options: options, format: SourceFormat(url: fileURL)))
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
        guard !Task.isCancelled else { return }
        guard let data else {
            // Agents and editors often save by replacing the file, so it can be missing for a moment.
            try? await Task.sleep(for: .milliseconds(500))
            if !FileManager.default.fileExists(atPath: url.path) { fileGone = true }
            return
        }
        fileGone = false
        readFromDiskAt = .now
        let newText = String(decoding: data, as: UTF8.self)
        guard newText != text else { return }
        let previous = text
        text = newText
        controller.send(.render(markdown: shownMarkdown, options: options, format: SourceFormat(url: fileURL)))
        // What just changed glows, whatever the person has read.
        let written = await Task.detached { ChangeDiff.changes(from: previous, to: newText) }.value
        let lines = (written.added.map(\.start) + written.changed.map(\.start)).sorted()
        if !lines.isEmpty {
            lastWrittenLine = lines.last
            controller.send(.markLive(lines: lines))
            controller.send(.setWriting(isBeingWritten, lastLine: lastWrittenLine))
            if following, writingAgent != nil, let last = lines.last { controller.send(.follow(line: last)) }
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
            copy(value)
        case let .saveComment(line, quote, body, id):
            guard let document = libraryDocument else { return }
            if let id, let existing = comments.first(where: { $0.id == id })?.comment {
                library.editComment(existing, body: body)
            } else {
                library.addComment(to: document, quote: quote, line: line, body: body, text: text)
            }
        case let .resolveComment(id):
            guard let existing = comments.first(where: { $0.id == id })?.comment else { return }
            library.setResolved(existing, true)
        case .showShortcuts:
            if let filesChrome { filesChrome.showOverlay(.shortcuts) } else { overlay = .shortcuts }
        case .toggleFollow:
            toggleFollow()
        case let .toggleTask(line, checked):
            Task { await tick(line: line, checked: checked) }
        case let .stepFile(by):
            onStepFile?(by)
        case let .acceptChange(kind, line):
            acceptChange(kind: kind, line: line)
        case let .noticeAction(id):
            switch id {
            case "showAll": showAll = true
            case "reviewDone": if let documentKey { AppServices.reviews.finish(documentKey: documentKey) }
            case "find": findMovedFile()
            case "close": if let onClose { onClose() } else { dismiss() }
            default: break
            }
        case let .composing(active):
            composing = active
        case let .copyPrompt(line, quote):
            let block = CommentAnchor.block(containing: line, in: text)
            let path = libraryDocument?.relativePath ?? fileURL?.lastPathComponent ?? ""
            copy(PromptBuilder.reference(path: path, lineStart: block?.startLine ?? line, lineEnd: block?.endLine ?? line, quote: quote))
        case .markRead:
            guard let document = libraryDocument else { return }
            library.markRead(document, text: text)
        case let .scrollLine(line):
            scrolledLine = line
        case .rendered:
            if takesFocus, let window = controller.webView.window, window.firstResponder !== controller.webView {
                window.makeFirstResponder(controller.webView)
            }
        default:
            break
        }
    }

    /// A link like "../specs/api.md" or "/docs/plan.md#steps", resolved against this file. Nil for anything else.
    private func localMarkdownURL(_ href: String) -> URL? {
        guard let fileURL, URL(string: href)?.scheme == nil else { return nil }
        let raw = String(href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let path = raw.removingPercentEncoding ?? raw
        guard FolderScanner.isMarkdown(URL(fileURLWithPath: path)) else { return nil }
        let base = path.hasPrefix("/")
            ? (assetRoot ?? fileURL.deletingLastPathComponent())
            : fileURL.deletingLastPathComponent()
        return base.appending(path: String(path.drop { $0 == "/" })).standardizedFileURL
    }
}
