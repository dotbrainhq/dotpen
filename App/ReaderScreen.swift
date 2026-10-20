import AppKit
import DotMDCore
import DotMDRender
import SwiftUI

struct ReaderScreen: View {
    let fileURL: URL?

    @State private var controller = ReaderController()
    @State private var text: String
    @AppStorage("readingOptions") private var options = ReadingOptions()
    @State private var showingReadingOptions = false

    init(file: MarkdownFile, fileURL: URL?) {
        self.fileURL = fileURL
        _text = State(initialValue: file.text)
    }

    var body: some View {
        ReaderView(controller: controller)
            .navigationTitle(fileURL?.lastPathComponent ?? "Untitled")
            .navigationSubtitle(fileURL.map { $0.deletingLastPathComponent().path(percentEncoded: false) } ?? "")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingReadingOptions.toggle()
                    } label: {
                        Text("Aa").font(.system(size: 13, weight: .semibold, design: .serif))
                    }
                    .help("Text size, font and width")
                    .accessibilityLabel("Reading options")
                    .popover(isPresented: $showingReadingOptions, arrowEdge: .bottom) {
                        ReadingOptionsPopover(options: $options)
                    }
                }
            }
            .preferredColorScheme(windowScheme)
            .onAppear(perform: start)
            .task(id: fileURL) { await watch() }
            .onChange(of: options) { _, newValue in
                controller.send(.setReadingOptions(newValue))
            }
    }

    /// The window follows the page: Night is dark, White and Paper are light, Auto follows the system.
    private var windowScheme: ColorScheme? {
        switch options.paper {
        case .night: .dark
        case .white, .paper: .light
        case .auto: nil
        }
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
            reload(from: fileURL)
        }
    }

    private func reload(from url: URL) {
        guard let newText = try? String(contentsOf: url, encoding: .utf8), newText != text else { return }
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
