import DotPenBridge
import DotPenCore
import DotPenRender
import SwiftUI

/// What a window can show over everything: the ⌘K palette or the keyboard shortcuts.
enum WindowOverlay: Equatable {
    case palette, shortcuts
}

/// What the reader in the key window offers the palette and the menus: its headings, and its actions.
struct ReaderCommands {
    var headings: [DocumentHeading]
    var reveal: (Int) -> ()
    var send: (() -> ())?
    var markRead: (() -> ())?
    var copyPrompt: (() -> ())?
    var exportPDF: (() -> ())?
    var showingSource = false
    var toggleSource: (() -> ())?
}

extension FocusedValues {
    @Entry var readerCommands: ReaderCommands?
    /// Shows the palette or the shortcuts in the key window.
    @Entry var showOverlay: ((WindowOverlay) -> ())?
}

/// One thing the palette can run, with the shortcut that does the same.
struct PaletteCommand: Identifiable {
    let title: String
    var shortcut: String?
    let action: () -> ()

    var id: String { title }
}

extension View {
    /// The window's overlay layer: the scrim, then the palette or the shortcuts. A click on the scrim closes it.
    func windowOverlays(_ overlay: Binding<WindowOverlay?>, commands: [PaletteCommand] = [], open: @escaping (DotPenCore.Document, Bool) -> ()) -> some View {
        modifier(WindowOverlays(overlay: overlay, commands: commands, open: open))
    }
}

private struct WindowOverlays: ViewModifier {
    @Binding var overlay: WindowOverlay?
    let commands: [PaletteCommand]
    let open: (DotPenCore.Document, Bool) -> ()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if let overlay {
                ZStack(alignment: overlay == .palette ? .top : .center) {
                    Palette.scrim
                        .contentShape(Rectangle())
                        .onTapGesture(perform: close)
                        .transition(.opacity)
                    switch overlay {
                    case .palette:
                        CommandPalette(windowCommands: commands, open: open, close: close)
                            .padding(.top, 120)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985)).combined(with: .offset(y: 6)))
                    case .shortcuts:
                        ShortcutsOverlay(close: close)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                    }
                }
                .ignoresSafeArea()
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22), value: overlay)
    }

    private func close() {
        overlay = nil
    }
}

/// The prototype's `.pal`: recent files first, then the reader's headings and commands. Type to search all three.
struct CommandPalette: View {
    let windowCommands: [PaletteCommand]
    let open: (DotPenCore.Document, Bool) -> ()
    let close: () -> ()

    @Environment(Library.self) private var library
    @Environment(AgentActivity.self) private var activity
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.readerCommands) private var reader
    @FocusedValue(\.showOverlay) private var showOverlay
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var fieldFocused
    @Environment(\.colorScheme) private var colorScheme

    private enum Row: Identifiable {
        case file(DotPenCore.Document)
        case heading(DocumentHeading)
        case command(PaletteCommand)

        var id: String {
            switch self {
            case let .file(document): "file \(document.key)"
            case let .heading(heading): "heading \(heading.line)"
            case let .command(command): "command \(command.title)"
            }
        }
    }

    private struct Group: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    var body: some View {
        let groups = self.groups
        let rows = groups.flatMap(\.rows)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Icon("search", size: 18)
                    .foregroundStyle(Palette.ink4)
                TextField("Open a file, jump to a heading, or run a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.ink)
                    .focused($fieldFocused)
                    // On the field itself: a text field takes Return and the arrows before its parent sees them.
                    .onKeyPress(.downArrow) {
                        selected = min(selected + 1, max(rows.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selected = max(selected - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.return, phases: .down) { press in
                        if rows.indices.contains(selected) { run(rows[selected], newWindow: press.modifiers.contains(.command)) }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
                    .onSubmit {
                        if rows.indices.contains(selected) { run(rows[selected], newWindow: false) }
                    }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .overlay(alignment: .bottom) { Palette.line.frame(height: 0.5) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(group.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Palette.ink4)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                ForEach(group.rows) { row in
                                    let index = rows.firstIndex { $0.id == row.id } ?? 0
                                    rowView(row, isSelected: index == selected)
                                        .id(row.id)
                                        .onTapGesture { run(row, newWindow: false) }
                                }
                            }
                            .padding(EdgeInsets(top: 8, leading: 8, bottom: 4, trailing: 8))
                        }
                        if rows.isEmpty {
                            Text("Nothing matches \u{201C}\(query)\u{201D}")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.ink4)
                                .padding(18)
                        }
                    }
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: selected) { _, index in
                    if rows.indices.contains(index) { proxy.scrollTo(rows[index].id) }
                }
            }
            HStack(spacing: 16) {
                Text("↑↓ move")
                Text("↩ open")
                Text("⌘↩ new window")
                Text("esc close")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .overlay(alignment: .top) { Palette.line.frame(height: 0.5) }
        }
        .frame(width: 560)
        .background(Palette.pop, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .modifier(ShadowThree(shape: RoundedRectangle(cornerRadius: 16), fill: Palette.pop, dark: colorScheme == .dark))
        .defaultFocus($fieldFocused, true)
        .task {
            // The palette arrives during the overlay's transition, before its field is in the window, so focus set on
            // appear is lost and keys keep going to the page. A beat later the field takes them.
            try? await Task.sleep(for: .milliseconds(50))
            fieldFocused = true
        }
        .onChange(of: query) { selected = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open anything")
    }

    // MARK: Rows

    private var groups: [Group] {
        let documents = library.folders.flatMap(\.documents)
        let commands = allCommands
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            // Unread first, newest change first; then what you read most recently.
            let unread = documents.filter { $0.readState != .read }.sorted { $0.modifiedAt > $1.modifiedAt }
            let read = documents.filter { $0.readState == .read }.sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
            return [
                Group(title: "Recent", rows: (unread + read).prefix(5).map(Row.file)),
                Group(title: "Commands", rows: commands.prefix(3).map(Row.command)),
            ]
        }
        func ranked<T>(_ items: [T], limit: Int, text: (T) -> String) -> [T] {
            items.compactMap { item in FuzzyMatch.score(trimmed, in: text(item)).map { (item, $0) } }
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map(\.0)
        }
        let files = ranked(documents, limit: 6) { ($0.title ?? "") + " " + $0.relativePath }
        let headings = ranked(reader?.headings ?? [], limit: 5) { $0.title }
        let matching = ranked(commands, limit: 5) { $0.title }
        return [
            Group(title: "Files", rows: files.map(Row.file)),
            Group(title: "Headings", rows: headings.map(Row.heading)),
            Group(title: "Commands", rows: matching.map(Row.command)),
        ].filter { !$0.rows.isEmpty }
    }

    /// The window's commands, the reader's, then the app's, each once.
    private var allCommands: [PaletteCommand] {
        var commands = windowCommands
        if let reader {
            if let send = reader.send { commands.append(PaletteCommand(title: "Send to agent", shortcut: "⌘↩", action: send)) }
            if let markRead = reader.markRead { commands.append(PaletteCommand(title: "Mark as read", shortcut: "⇧⌘M", action: markRead)) }
            if let copyPrompt = reader.copyPrompt { commands.append(PaletteCommand(title: "Copy as prompt", shortcut: "⇧⌘C", action: copyPrompt)) }
            if let exportPDF = reader.exportPDF { commands.append(PaletteCommand(title: "Export as PDF…", shortcut: "⌘E", action: exportPDF)) }
            if let toggleSource = reader.toggleSource {
                commands.append(PaletteCommand(title: reader.showingSource ? "Hide source" : "Show source", shortcut: "⌘U", action: toggleSource))
            }
        }
        commands.append(PaletteCommand(title: "Open a file…", shortcut: "⌘O") { FileActions.openFilePanel() })
        if library.pausedUntil == nil {
            commands.append(PaletteCommand(title: "Pause watching for 1 hour") { library.pauseWatching(for: .seconds(3600)) })
        } else {
            commands.append(PaletteCommand(title: "Resume watching") { Task { await library.resumeWatching() } })
        }
        commands.append(PaletteCommand(title: "Keyboard shortcuts", shortcut: "⌘/") { showOverlay?(.shortcuts) })
        commands.append(PaletteCommand(title: "Settings…", shortcut: "⌘,") { openWindow(id: "settings") })
        return commands
    }

    @ViewBuilder private func rowView(_ row: Row, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            switch row {
            case let .file(document):
                fileIcon(document)
                Text(document.title ?? (document.relativePath as NSString).lastPathComponent)
                    .foregroundStyle(Palette.ink)
                Text(library.folders.first { $0.id == document.folderID }?.folder.name ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.ink4)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    switch document.readState {
                    case .new, .changed:
                        Text(document.readState == .new ? "new" : "changed")
                        Circle().fill(Palette.accent).frame(width: 7, height: 7)
                    case .read:
                        Text(ReadingLabels.commentTime(document.lastReadAt ?? document.modifiedAt))
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink4)
            case let .heading(heading):
                Icon("doc", size: 16).foregroundStyle(Palette.ink3)
                Text(heading.title).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text("line \(heading.line)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink4)
            case let .command(command):
                Icon("spark", size: 16).foregroundStyle(Palette.ink3)
                Text(command.title).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink4)
                }
            }
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(isSelected ? Palette.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    /// The agent's badge when its log says it wrote the file, else the file's kind.
    @ViewBuilder private func fileIcon(_ document: DotPenCore.Document) -> some View {
        if let url = library.url(for: document), let agent = activity.writer(for: url)?.agent {
            Text(agent == .claudeCode ? "CC" : "CX")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.window)
                .frame(width: 16, height: 16)
                .background(agent == .claudeCode ? Palette.agentClaude : Palette.agentCodex, in: RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel(agent.name)
        } else {
            Icon(document.kind.iconName, size: 16).foregroundStyle(Palette.ink3)
        }
    }

    private func run(_ row: Row, newWindow: Bool) {
        close()
        switch row {
        case let .file(document): open(document, newWindow)
        case let .heading(heading): reader?.reveal(heading.line)
        case let .command(command): command.action()
        }
    }
}

/// The prototype's `.keys`: every shortcut dotPen has, in three columns.
struct ShortcutsOverlay: View {
    let close: () -> ()
    @Environment(\.colorScheme) private var colorScheme

    private let columns: [(title: String, rows: [(String, [String])])] = [
        ("Move around", [
            ("Next file", ["J"]),
            ("Previous file", ["K"]),
            ("Next change", ["N"]),
            ("Previous change", ["⇧", "N"]),
            ("Open anything", ["⌘", "K"]),
        ]),
        ("Review", [
            ("Comment", ["C"]),
            ("Send to agent", ["⌘", "↩"]),
            ("Mark as read", ["⇧", "⌘", "M"]),
            ("Tick task", ["Space"]),
            ("Copy as prompt", ["⇧", "⌘", "C"]),
        ]),
        ("View", [
            ("File list", ["⌘", "⌥", "S"]),
            ("Bigger text", ["⌘", "+"]),
            ("Smaller text", ["⌘", "−"]),
            ("Follow agent", ["F"]),
            ("Show source", ["⌘", "U"]),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Keyboard shortcuts")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Press ? any time")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink4)
            }
            HStack(alignment: .top, spacing: 22) {
                ForEach(columns, id: \.title) { column in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(column.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.ink4)
                            .padding(.bottom, 8)
                        ForEach(column.rows, id: \.0) { title, keys in
                            // The prototype's `.kr`: the title takes the room, the keys sit at the end, 10 apart.
                            HStack(spacing: 10) {
                                Text(title).font(.system(size: 12.5)).foregroundStyle(Palette.ink).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 3) {
                                    ForEach(Array(keys.enumerated()), id: \.offset) { _, key in KeyCap(key) }
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(EdgeInsets(top: 22, leading: 26, bottom: 20, trailing: 26))
        .frame(width: 640)
        .background(Palette.pop, in: RoundedRectangle(cornerRadius: 18))
        .modifier(ShadowThree(shape: RoundedRectangle(cornerRadius: 18), fill: Palette.pop, dark: colorScheme == .dark))
        .background {
            Button("Close", action: close)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

/// The prototype's `kbd`: 20 points tall on a soft fill with a line under it.
private struct KeyCap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .bottom) {
                Palette.line.frame(height: 1).clipShape(RoundedRectangle(cornerRadius: 5))
            }
    }
}

/// Menu commands for the palette, the shortcuts, the reader and text size, so each has a menu item and a key.
struct PaletteCommands: Commands {
    @FocusedValue(\.readerCommands) private var reader
    @FocusedValue(\.showOverlay) private var showOverlay
    @AppStorage("readingOptions") private var options = ReadingOptions()

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Mark as Read") { reader?.markRead?() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(reader?.markRead == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy as Prompt") { reader?.copyPrompt?() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(reader?.copyPrompt == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("Bigger Text") { step(1) }
                .keyboardShortcut("+")
                .disabled(options.size == ReadingOptions.Size.allCases.last)
            Button("Smaller Text") { step(-1) }
                .keyboardShortcut("-")
                .disabled(options.size == ReadingOptions.Size.allCases.first)
            Divider()
            Button(reader?.showingSource == true ? "Hide Source" : "Show Source") { reader?.toggleSource?() }
                .keyboardShortcut("u")
                .disabled(reader?.toggleSource == nil)
            Divider()
        }
        CommandMenu("Go") {
            Button("Open Quickly…") { showOverlay?(.palette) }
                .keyboardShortcut("k")
                .disabled(showOverlay == nil)
        }
        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") { showOverlay?(.shortcuts) }
                .keyboardShortcut("/")
                .disabled(showOverlay == nil)
        }
    }

    private func step(_ delta: Int) {
        let sizes = ReadingOptions.Size.allCases
        guard let index = sizes.firstIndex(of: options.size) else { return }
        options.size = sizes[min(max(index + delta, 0), sizes.count - 1)]
    }
}
