import AppKit
import DotMDCore
import DotMDRender
import SwiftUI

struct ReaderScreen: View {
    let fileURL: URL?

    @Environment(Library.self) private var library
    @State private var controller = ReaderController()
    @State private var text: String
    @AppStorage("readingOptions") private var options = ReadingOptions()
    @State private var showingReadingOptions = false
    @State private var documentKey: Int64?

    init(text: String, fileURL: URL?) {
        self.fileURL = fileURL
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
            .onChange(of: folderSignature, initial: true) { _, _ in
                resolveDocument()
            }
            .onChange(of: readState, initial: true) { _, state in
                markReadIfNeeded(state)
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

    /// Reading a file in DotMD marks it read, including after it changes while open.
    private func markReadIfNeeded(_ state: ReadState?) {
        guard let state, state != .read, let documentKey, let document = library.document(key: documentKey) else { return }
        library.markRead(document)
    }

    private func start() {
        controller.onMessage = handle
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
        text = newText
        controller.send(.render(markdown: newText, options: options))
    }

    private func handle(_ message: ReaderMessage) {
        switch message {
        case let .linkActivated(href):
            guard let url = URL(string: href), let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else { return }
            NSWorkspace.shared.open(url)
        case let .copyText(value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        default:
            break
        }
    }
}
