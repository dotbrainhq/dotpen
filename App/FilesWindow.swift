import AppKit
import DotMDCore
import SwiftUI

/// The Files layout: watched folders on the left, the selected document on the right.
///
/// Laid out by hand rather than with NavigationSplitView: the prototype's sidebar is exactly 272 points with the
/// window buttons inside its panel, while the system split view holds its sidebar at its own width and keeps the
/// buttons in a title bar above it.
struct FilesWindow: View {
    @Environment(Library.self) private var library
    @Environment(FilesNavigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Int64?
    @SceneStorage("filesSidebarVisible") private var sidebarVisible = true
    @AppStorage("fileSort") private var sort = FileSortOrder.lastChanged
    @AppStorage("showTitles") private var showTitles = false
    @State private var filter = FileFilter()
    /// The Send sheet, over the whole window with the scrim behind it.
    @State private var sheet: AnyView?

    /// The prototype's sidebar column.
    static let sidebarWidth: CGFloat = 272

    var body: some View {
        Group {
            if isFirstLaunch {
                FirstLaunchView()
            } else {
                HStack(spacing: 0) {
                    if sidebarVisible {
                        sidebar
                            .frame(width: Self.sidebarWidth)
                            .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                    }
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .overlay(alignment: .top) {
            if let sheet {
                ZStack(alignment: .top) {
                    Palette.scrim
                        .contentShape(Rectangle())
                        .onTapGesture { showSheet(nil) }
                        .transition(.opacity)
                    // Hangs from the bottom of the 52 point bar, as the prototype's sheet does.
                    sheet
                        .padding(.top, 52)
                        .transition(reduceMotion ? .opacity : .offset(y: -16).combined(with: .opacity))
                }
            }
        }
        .background(Palette.window)
        .ignoresSafeArea()
        .background {
            // The prototype puts the window buttons inside the sidebar panel, or in the bar when the list is hidden
            // and on first launch.
            WindowButtons(closeCenter: sidebarVisible && !isFirstLaunch ? CGPoint(x: 30, y: 30) : CGPoint(x: 22, y: 26))
        }
        .environment(\.filesChrome, chrome)
        .onChange(of: navigator.requested, initial: true) { _, requested in
            // The menu bar item asked for a file.
            guard let requested else { return }
            selection = requested
            navigator.requested = nil
        }
        .focusedSceneValue(\.toggleFiles, toggleFiles)
        .frame(minWidth: 760, minHeight: 480)
    }

    /// No folder watched yet. Until the library has read its stored folders an empty list means nothing, so a
    /// returning person never sees first launch flash by.
    private var isFirstLaunch: Bool {
        library.hasLoaded && library.folders.isEmpty
    }

    private var chrome: FilesChrome {
        FilesChrome(sidebarVisible: sidebarVisible, toggleSidebar: toggleFiles, showSheet: showSheet)
    }

    /// The prototype's `.side-in`: a rounded panel 8 points in from the window's top, left and bottom, padded
    /// 16 on top and 8 elsewhere. Its first 26 points hold the window buttons.
    private var sidebar: some View {
        VStack(spacing: 0) {
            // 26 in the prototype (12 point buttons, 14 below), less half a point for how a browser rounds the
            // 11 point header's line box, so the header and rows land on the prototype's pixels.
            Color.clear
                .frame(height: 25.5)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
            ListHeader(sort: $sort, showTitles: $showTitles)
            FileList(selection: $selection, sort: sort, showTitles: showTitles, filter: filter)
                .frame(maxHeight: .infinity)
            FilterBar(filter: $filter, addFolder: addFolder)
        }
        .padding(EdgeInsets(top: 16, leading: 8, bottom: 8, trailing: 8))
        .background {
            let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
            shape
                .fill(Palette.sidebar)
                .overlay(shape.strokeBorder(Palette.sidebarEdge, lineWidth: 0.5))
        }
        .padding(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 0))
    }

    private var selectedDocument: DotMDCore.Document? {
        guard let selection else { return nil }
        return library.folders.lazy.flatMap(\.documents).first { $0.key == selection }
    }

    @ViewBuilder private var detail: some View {
        if let document = selectedDocument {
            LibraryReader(document: document, openDocument: openDocument)
                .id(document.key)
        } else {
            VStack(spacing: 0) {
                TopBar(chrome: chrome, title: "", path: "") {
                    EmptyView()
                }
                ContentUnavailableView("Choose a file", systemImage: "doc.text", description: Text("Pick a Markdown file from the list."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("DotMD")
        }
    }

    private func showSheet(_ view: AnyView?) {
        sheet = view
    }

    private func toggleFiles() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.9)) {
            sidebarVisible.toggle()
        }
    }

    /// A relative link selects its file in the list when it's in a watched folder, and opens a window otherwise.
    private func openDocument(_ url: URL) {
        if let document = library.document(at: url) {
            selection = document.key
        } else {
            FileActions.openInNewWindow(url)
        }
    }

    private func addFolder() {
        guard let url = FolderPicker.chooseFolder(message: "Choose a folder to watch. DotMD lists every Markdown file inside it.") else { return }
        FileActions.watch(url, in: library)
    }
}

extension FocusedValues {
    @Entry var toggleFiles: (() -> ())?
}

/// View > Show Files (⌥⌘S): hides or shows the file list in the Files window, or opens that window from a document window.
struct FilesCommands: Commands {
    @FocusedValue(\.toggleFiles) private var toggleFiles
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(toggleFiles == nil ? "Show Files" : "Show or Hide Files") {
                if let toggleFiles { toggleFiles() } else { openWindow(id: "files") }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }
    }
}
