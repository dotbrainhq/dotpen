import DotMDCore
import SwiftUI

@main
struct DotMDApp: App {
    @State private var library: Library
    @State private var bridge: AgentBridge
    @State private var activity: AgentActivity

    init() {
        let library = Library.makeDefault()
        _library = State(initialValue: library)
        _bridge = State(initialValue: AgentBridge(library: library))
        _activity = State(initialValue: AgentActivity(library: library))
    }

    var body: some Scene {
        Window("DotMD", id: "files") {
            FilesWindow()
                .environment(library)
                .environment(bridge)
                .environment(activity)
                .task {
                    await library.start()
                    bridge.startIfEnabled()
                    activity.start()
                    #if DEBUG
                    await DebugWorkspace.open(in: library)
                    #endif
                }
        }
        // The prototype's window: 1200 by 806, with no title bar over the sidebar panel.
        .defaultSize(width: 1200, height: 806)
        .windowStyle(.hiddenTitleBar)
        .commands {
            FilesCommands()
            SettingsCommands()
        }

        // A plain window rather than the Settings scene, which keeps a title bar the prototype doesn't have.
        Window("Settings", id: "settings") {
            SettingsView()
                .environment(library)
                .environment(bridge)
                .environment(activity)
                .task {
                    await library.start()
                    bridge.startIfEnabled()
                    activity.start()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)

        DocumentGroup(viewing: MarkdownFile.self) { configuration in
            ReaderScreen(text: configuration.document.text, fileURL: configuration.fileURL)
                .background(WindowTabbing())
                .frame(minWidth: 560, minHeight: 480)
                .environment(library)
                .environment(bridge)
                .environment(activity)
                .task {
                    await library.start()
                    bridge.startIfEnabled()
                    activity.start()
                }
        }
        .commands { ExportCommands() }
    }
}
