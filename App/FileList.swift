import DotMDCore
import SwiftUI

/// The watched folders as an outline, drawn to match the prototype rather than a stock sidebar list.
/// Selection is the open file; focus is the row the keyboard is on, which can be a folder.
struct FileList: View {
    @Environment(Library.self) private var library
    @Binding var selection: Int64?
    let sort: FileSortOrder
    let showTitles: Bool
    let filter: FileFilter
    @State private var collapsed: Set<String> = []
    @State private var focusedRow: OutlineRowID?
    @FocusState private var listFocused: Bool
    /// The ring shows only after keyboard use, like the prototype's :focus-visible. A click hides it again.
    @State private var usingKeyboard = false
    @State private var typed = ""
    @State private var typedAt = Date.distantPast

    var body: some View {
        let selectedFolder = selection.flatMap { library.document(key: $0)?.folderID }
        let actions = OutlineActions(activate: { activate($0, fromKeyboard: false) })
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(library.folders, id: \.folder.path) { folder in
                        FolderSection(
                            folder: folder,
                            sort: sort,
                            showTitles: showTitles,
                            filter: filter,
                            collapsed: collapsedKeys(in: folder),
                            selection: selectedFolder == folder.id ? selection : nil,
                            focus: listFocused && usingKeyboard && focusedRow?.folderID == folder.id ? focusedRow : nil,
                            actions: actions
                        )
                        .equatable()
                    }
                    HiddenPathsNote()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .focusable(interactions: .edit)
                .focused($listFocused)
                .focusEffectDisabled()
                .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                    arrow(press.key, proxy: proxy)
                }
                .onKeyPress(keys: [.return, .space]) { press in
                    guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
                    return openFocused()
                }
                .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters).union(.symbols), phases: .down) { press in
                    typeSelect(press, proxy: proxy)
                }
            }
            // The prototype shows no scroll bar, and a visible one would narrow every row.
            .scrollIndicators(.never)
        }
        .onChange(of: listFocused) { _, focused in
            if focused { placeFocus() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Files")
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            for url in folders { FileActions.watch(url, in: library) }
            return !folders.isEmpty
        }
    }

    /// Every visible row in display order, built from the same groups the sections draw.
    private var visibleRows: [OutlineRow] {
        Outline.rows(for: library.folders, sort: sort, filter: filter, showTitles: showTitles, collapsed: collapsed)
    }

    /// Only this folder's keys, so another folder's toggle leaves this section unchanged.
    private func collapsedKeys(in folder: FolderState) -> Set<String> {
        let own = "\(folder.id)"
        return collapsed.filter { $0 == own || $0.hasPrefix(own + "/") }
    }

    private func setExpanded(_ row: OutlineRow, _ isOpen: Bool) {
        guard let key = row.id.expansionKey else { return }
        if isOpen { collapsed.remove(key) } else { collapsed.insert(key) }
    }

    /// A click, Return or VoiceOver's default action: opens a file, or opens or closes a folder.
    private func activate(_ row: OutlineRow, fromKeyboard: Bool) {
        focusedRow = row.id
        listFocused = true
        usingKeyboard = fromKeyboard
        switch row.content {
        case let .file(document): selection = document.key
        case .folder, .directory: setExpanded(row, !row.isExpanded)
        }
    }

    /// Gaining focus without a focused row, or with one that's no longer shown, starts at the open file.
    private func placeFocus() {
        let rows = visibleRows
        if let focusedRow, rows.contains(where: { $0.id == focusedRow }) { return }
        let selected = rows.first { if case let .file(document) = $0.content { document.key == selection } else { false } }
        focusedRow = selected?.id ?? rows.first?.id
    }

    private func moveFocus(to id: OutlineRowID?, proxy: ScrollViewProxy) {
        guard let id else { return }
        usingKeyboard = true
        focusedRow = id
        proxy.scrollTo(id)
    }

    private func arrow(_ key: KeyEquivalent, proxy: ScrollViewProxy) -> KeyPress.Result {
        let rows = visibleRows
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.id == focusedRow }
        switch key {
        case .upArrow:
            moveFocus(to: Outline.move(from: current.map { rows[$0].id }, by: -1, in: rows), proxy: proxy)
        case .downArrow:
            moveFocus(to: Outline.move(from: current.map { rows[$0].id }, by: 1, in: rows), proxy: proxy)
        case .rightArrow:
            guard let current, rows[current].isExpandable else { return .ignored }
            let row = rows[current]
            if !row.isExpanded {
                setExpanded(row, true)
            } else if current + 1 < rows.count, rows[current + 1].parent == row.id {
                moveFocus(to: rows[current + 1].id, proxy: proxy)
            }
        case .leftArrow:
            guard let current else { return .ignored }
            let row = rows[current]
            if row.isExpandable && row.isExpanded {
                setExpanded(row, false)
            } else {
                moveFocus(to: row.parent, proxy: proxy)
            }
        default:
            return .ignored
        }
        return .handled
    }

    private func openFocused() -> KeyPress.Result {
        guard let row = visibleRows.first(where: { $0.id == focusedRow }) else { return .ignored }
        activate(row, fromKeyboard: true)
        return .handled
    }

    /// Letters typed within a second of each other build one prefix; the focus jumps to the next row that starts with it.
    private func typeSelect(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        let now = Date()
        let fresh = now.timeIntervalSince(typedAt) > 1
        typed = (fresh ? "" : typed) + press.characters
        typedAt = now
        let match = Outline.typeSelect(typed, from: focusedRow, includingFocus: !fresh, in: visibleRows)
        moveFocus(to: match, proxy: proxy)
        return .handled
    }
}

/// What a row does when clicked. Kept out of FolderSection's equality: the closure writes through state storage,
/// so a section skipped with an older copy still acts on the current list.
struct OutlineActions {
    let activate: (OutlineRow) -> ()
}

/// One watched folder and its rows. SwiftUI skips its body while the folder, the list settings, its own collapsed
/// keys and its share of the selection and focus are unchanged, so a change in one folder doesn't redraw the others.
struct FolderSection: View, Equatable {
    let folder: FolderState
    let sort: FileSortOrder
    let showTitles: Bool
    let filter: FileFilter
    let collapsed: Set<String>
    /// The selected file's key, only when it is in this folder.
    let selection: Int64?
    /// The keyboard-focused row, only when it is in this folder and the list has focus.
    let focus: OutlineRowID?
    let actions: OutlineActions

    nonisolated static func == (lhs: FolderSection, rhs: FolderSection) -> Bool {
        lhs.folder == rhs.folder && lhs.sort == rhs.sort && lhs.showTitles == rhs.showTitles
            && lhs.filter == rhs.filter && lhs.collapsed == rhs.collapsed
            && lhs.selection == rhs.selection && lhs.focus == rhs.focus
    }

    var body: some View {
        let rows = Outline.rows(for: folder, sort: sort, filter: filter, showTitles: showTitles, collapsed: collapsed)
        // An explicit stack: `.equatable()` would otherwise wrap these rows in one with the default 8 point spacing.
        VStack(spacing: 0) {
            ForEach(rows) { row in
                rowView(row)
                    .id(row.id)
            }
            if folder.status == .ready && folder.documents.isEmpty && rows.first?.isExpanded == true {
                Text("No Markdown files yet")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 42)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder private func rowView(_ row: OutlineRow) -> some View {
        let focused = focus == row.id
        switch row.content {
        case .folder:
            FolderRow(folder: folder, isExpanded: row.isExpanded)
                .modifier(OutlineRowChrome(depth: row.depth, focused: focused, topMargin: 6))
                .onTapGesture { actions.activate(row) }
                .contextMenu { FolderMenu(folder: folder) }
                .disclosureAccessibility(row, actions: actions)
        case let .directory(path):
            DirectoryRow(path: path, isExpanded: row.isExpanded)
                .modifier(OutlineRowChrome(depth: row.depth, focused: focused))
                .onTapGesture { actions.activate(row) }
                .disclosureAccessibility(row, actions: actions)
        case let .file(document):
            let selected = selection == document.key
            FileRow(document: document, showTitles: showTitles, depth: row.depth, selected: selected, focused: focused)
                .onTapGesture { actions.activate(row) }
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { actions.activate(row) }
        }
    }
}

private extension View {
    /// Folder and subfolder rows read as buttons that open or close, with their state in the value.
    func disclosureAccessibility(_ row: OutlineRow, actions: OutlineActions) -> some View {
        accessibilityAddTraits(.isButton)
            .accessibilityAction { actions.activate(row) }
            .accessibilityAction(named: row.isExpanded ? "Collapse" : "Expand") { actions.activate(row) }
    }
}
