import AppKit
import DotMDBridge
import DotMDCore
import SwiftUI

/// Settings, drawn like the prototype's `.settings`: a bar with the window buttons and the tabs, the selected pane,
/// then the About footer. The prototype's Done button is left out: Mac settings windows close with the close button. Only the panes whose features exist are listed; the rest join as they ship.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case folders, integrations

        var id: String { rawValue }

        var title: String {
            switch self {
            case .folders: "Folders"
            case .integrations: "Integrations"
            }
        }

        var icon: String {
            switch self {
            case .folders: "folders"
            case .integrations: "plug"
            }
        }
    }

    @SceneStorage("settingsPane") private var pane = Pane.folders
    /// The hidden title bar's height. The content runs up under it, and the window sizes to the content alone.
    @State private var titleBarInset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            bar
            switch pane {
            case .folders: FoldersSettings()
            case .integrations: IntegrationsSettings()
            }
            AboutFooter()
        }
        .frame(width: 640)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, -titleBarInset)
        .background(Palette.window.ignoresSafeArea())
        // The inset arrives in steps as the window opens. Keeping the largest settles on the title bar's height:
        // following every reading would loop, since pulling the content up changes the reading.
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { inset in
            titleBarInset = max(titleBarInset, inset.rounded())
        }
        .background {
            // The prototype's lights sit in the bar's top padding: 16 in, 14 down.
            WindowButtons(closeCenter: CGPoint(x: 22, y: 20))
        }
    }

    /// The prototype's `.st-bar`: the tabs centered, with the window buttons at the left.
    private var bar: some View {
        HStack(spacing: 4) {
            ForEach(Pane.allCases) { item in
                Button { pane = item } label: {
                    VStack(spacing: 3) {
                        Icon(item.icon, size: 22)
                        Text(item.title)
                            .font(.system(size: 11.5))
                    }
                }
                .buttonStyle(SettingsTabStyle(isSelected: pane == item))
                // The selected fill already marks the tab; the prototype draws no focus ring on it.
                .focusEffectDisabled()
            }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16))
        .frame(maxWidth: .infinity)
        .background {
            Palette.bar
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
        .overlay(alignment: .bottom) {
            Palette.line.frame(height: 0.5)
        }
    }
}

/// The prototype's `.st-tab`: icon over label, ink-3, and green on a soft fill when selected.
private struct SettingsTabStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Palette.accentInk : Palette.ink3)
            // 5 below in the prototype; SF Pro's line at 11.5 points runs half a point taller than a browser's.
            .padding(EdgeInsets(top: 6, leading: 12, bottom: 4.5, trailing: 12))
            .background(isSelected ? Palette.fill : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The watched folders, then the ignored-paths switch and a way to watch another folder, as `.st-row` rows.
private struct FoldersSettings: View {
    @Environment(Library.self) private var library
    @State private var folderToRemove: FolderState?

    /// Past this many folders the rows scroll, so the window stays on screen.
    private let visibleFolders = 7

    var body: some View {
        @Bindable var library = library
        VStack(spacing: 0) {
            if library.folders.count > visibleFolders {
                ScrollView {
                    folderRows
                }
                .frame(height: CGFloat(visibleFolders) * 58)
                SettingsDivider()
            } else if !library.folders.isEmpty {
                folderRows
                SettingsDivider()
            }
            SettingsRow(title: "Show ignored paths", detail: "List node_modules, build folders and paths in .gitignore too.") {
                Toggle("Show ignored paths", isOn: $library.showIgnored)
                    .toggleStyle(SwitchToggleStyle())
            }
            SettingsDivider()
            SettingsRow(title: "Watch another folder", detail: "DotMD lists every Markdown file inside it and watches it for changes.") {
                Button("Choose…", action: addFolder)
                    .buttonStyle(FormButtonStyle(height: 26, fontSize: 12))
            }
        }
        .padding(EdgeInsets(top: 18, leading: 26, bottom: 22, trailing: 26))
        .alert(
            "Stop watching \(folderToRemove?.folder.name ?? "this folder")?",
            isPresented: Binding(get: { folderToRemove != nil }, set: { if !$0 { folderToRemove = nil } }),
            presenting: folderToRemove
        ) { folder in
            Button("Stop Watching", role: .destructive) { library.removeFolder(folder.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("DotMD forgets which files you've read in it. Your files stay as they are.")
        }
    }

    private var folderRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(library.folders.enumerated()), id: \.element.id) { index, folder in
                if index > 0 { SettingsDivider() }
                WatchedFolderRow(folder: folder, remove: { folderToRemove = folder }, reconnect: { reconnect(folder) })
            }
        }
    }

    private func addFolder() {
        guard let url = FolderPicker.chooseFolder(message: "Choose a folder to watch. DotMD lists every Markdown file inside it.") else { return }
        FileActions.watch(url, in: library)
    }

    private func reconnect(_ folder: FolderState) {
        let path = URL(fileURLWithPath: folder.folder.path)
        guard let url = FolderPicker.chooseFolder(
            message: "Choose \(folder.folder.name) again so DotMD can read it.",
            prompt: "Reconnect",
            startingAt: path.deletingLastPathComponent()
        ) else { return }
        Task { try? await library.reconnect(folder.id, to: url) }
    }
}

/// The agent bridge's switch, then how each agent connects once it's on, then the agent logs DotMD may read.
private struct IntegrationsSettings: View {
    @Environment(AgentBridge.self) private var bridge
    @Environment(AgentActivity.self) private var activity
    @Environment(SpotlightIndex.self) private var spotlight

    /// Writes cli/dotmd to /usr/local/bin. The person runs it; a sandboxed app can't install a command.
    static let installCommand = #"printf '%s\n' '#!/bin/sh' '[ "$#" -eq 0 ] && set -- .' 'exec open -b app.dotmd.DotMD "$@"' | sudo tee /usr/local/bin/dotmd > /dev/null && sudo chmod +x /usr/local/bin/dotmd"#

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title: "Spotlight", detail: "Find headings and text from watched files in Spotlight.") {
                Toggle("Spotlight", isOn: Binding(get: { spotlight.isEnabled }, set: { spotlight.setEnabled($0) }))
                    .toggleStyle(SwitchToggleStyle())
            }
            SettingsDivider()
            SettingsRow(title: "Shortcuts", detail: "Actions: Open file, Get changes since last read, List open tasks, Send comments to agent.") {
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(FormButtonStyle(height: 26, fontSize: 12))
            }
            SettingsDivider()
            SettingsRow(title: "Command line", detail: "Run the copied command once in Terminal. Then try dotmd plan.md.") {
                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.installCommand, forType: .string)
                }
                .buttonStyle(FormButtonStyle(height: 26, fontSize: 12))
                .accessibilityLabel("Copy the command line install command")
            }
            SettingsDivider()
            SettingsRow(title: "Agent bridge", detail: "An MCP server so your agents can read your comments and resolve them.") {
                Toggle("Agent bridge", isOn: Binding(get: { bridge.isEnabled }, set: { bridge.setEnabled($0) }))
                    .toggleStyle(SwitchToggleStyle())
            }
            switch bridge.state {
            case .running, .starting:
                // Each agent adds the bridge its own way, and people use different ones.
                ForEach(bridge.connections) { connection in
                    SettingsDivider()
                    SettingsRow(title: connection.agent, detail: connection.detail) {
                        Button(connection.button) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(connection.text, forType: .string)
                        }
                        .buttonStyle(FormButtonStyle(height: 26, fontSize: 12))
                        .accessibilityLabel("\(connection.button) for \(connection.agent)")
                    }
                }
            case let .failed(message):
                SettingsDivider()
                SettingsRow(title: "The bridge couldn't start", detail: message) {
                    Button("Try Again") { bridge.start() }
                        .buttonStyle(FormButtonStyle(height: 26, fontSize: 12))
                }
            case .off:
                EmptyView()
            }
            // Reading an agent's logs is how DotMD names who wrote a file and follows a file while it's written.
            ForEach(Agent.allCases, id: \.self) { agent in
                SettingsDivider()
                SettingsRow(title: "\(agent.name) sessions",
                            detail: "Name \(agent.name) on the files it writes. Reads \(AgentActivity.logFolderName(for: agent)) on this Mac.") {
                    if activity.granted.contains(agent) {
                        Button("Stop Reading") { activity.revokeAccess(to: agent) }
                            .buttonStyle(FormButtonStyle(height: 26, fontSize: 12))
                            .accessibilityLabel("Stop reading \(agent.name) sessions")
                    } else {
                        Button("Allow Access…") { activity.grantAccess(to: agent) }
                            .buttonStyle(FormButtonStyle(height: 26, fontSize: 12))
                            .accessibilityLabel("Allow access to \(agent.name) sessions")
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 18, leading: 26, bottom: 22, trailing: 26))
    }
}

/// A watched folder: its color and name, where it lives and how many Markdown files it holds.
private struct WatchedFolderRow: View {
    let folder: FolderState
    let remove: () -> ()
    let reconnect: () -> ()

    var body: some View {
        SettingsRow(title: folder.folder.name, detail: detail) {
            if folder.accessLost {
                HStack(spacing: 10) {
                    Icon("warn", size: 14)
                        .foregroundStyle(Palette.warn)
                    Button("Reconnect…", action: reconnect)
                        .buttonStyle(FormButtonStyle(height: 26, fontSize: 12))
                }
            } else {
                Button("Remove", action: remove)
                    .buttonStyle(FormButtonStyle(height: 26, fontSize: 12))
                    .accessibilityLabel("Stop watching \(folder.folder.name)")
            }
        } leading: {
            // The same marks as the folder's row in the list: its own color, and the amber warning when lost.
            Icon("folder", size: 16)
                .foregroundStyle(folder.folder.color.color)
        }
    }

    private var detail: String {
        let path = RealHome.abbreviate(URL(fileURLWithPath: folder.folder.path))
        if folder.accessLost { return "\(path) · Access lost" }
        let count = folder.documents.count
        return "\(path) · \(count == 1 ? "1 Markdown file" : "\(count) Markdown files")"
    }
}

/// The prototype's `.st-row`: a bold title over a quiet line, with the control on the right.
private struct SettingsRow<Control: View, Leading: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control
    @ViewBuilder let leading: Leading

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink3)
                        // The prototype's 1.45 line height: the extra between lines, and the browser's half
                        // leading above and below, which SwiftUI leaves out.
                        .lineSpacing(3.1)
                        .padding(.top, 0.5)
                        .padding(.bottom, 1.75)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
    }
}

extension SettingsRow where Leading == EmptyView {
    init(title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.init(title: title, detail: detail, control: control, leading: { EmptyView() })
    }
}

/// The half point line between `.st-row` rows.
private struct SettingsDivider: View {
    var body: some View {
        Palette.lineSoft.frame(height: 0.5)
    }
}

/// The prototype's `.st-about`: the icon, the version and tagline, and a link to the project.
private struct AboutFooter: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        HStack(spacing: 12) {
            Image("BrandIconSmall")
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("DotMD \(version)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Read what your agents write. Open source, nothing leaves your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("View on GitHub") {
                if let url = URL(string: "https://github.com/dotbrainhq/dotmd") { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(FormButtonStyle(height: 26, fontSize: 12))
        }
        .padding(EdgeInsets(top: 14, leading: 26, bottom: 18, trailing: 26))
        .background(Palette.bar)
        .overlay(alignment: .top) {
            Palette.line.frame(height: 0.5)
        }
    }
}

/// DotMD > Settings… (⌘,) opens the Settings window above.
struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: "settings") }
                .keyboardShortcut(",")
        }
    }
}
