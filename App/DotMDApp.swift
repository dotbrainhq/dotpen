import CoreSpotlight
import DotMDCore
import SwiftUI

@main
struct DotMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var library = AppServices.library
    @State private var bridge = AppServices.bridge
    @State private var activity = AppServices.activity
    @State private var spotlight = AppServices.spotlight
    @State private var navigator = AppServices.navigator

    var body: some Scene {
        Window("DotMD", id: "files") {
            FilesWindow()
                .environment(navigator)
                .environment(library)
                .environment(bridge)
                .environment(activity)
                .task {
                    await AppServices.start()
                    #if DEBUG
                    await DebugWorkspace.open(in: library)
                    #endif
                }
                .onChange(of: library.folders) { spotlight.update() }
                // A Spotlight result selects its file here.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                          let document = library.document(at: SpotlightIndex.fileURL(fromIdentifier: identifier)) else { return }
                    navigator.requested = document.key
                }
        }
        // The prototype's window: 1200 by 806, with no title bar over the sidebar panel.
        .defaultSize(width: 1200, height: 806)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [CSSearchableItemActionType])
        .commands {
            FilesCommands()
            SettingsCommands()
            PaletteCommands()
        }

        // A plain window rather than the Settings scene, which keeps a title bar the prototype doesn't have.
        Window("Settings", id: "settings") {
            SettingsView()
                .environment(library)
                .environment(bridge)
                .environment(activity)
                .environment(spotlight)
                .task { await AppServices.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)

        // The Trail mark in the menu bar: who's writing, what's new, and a way to pause watching.
        MenuBarExtra {
            MenuBarMenu()
                .environment(library)
                .environment(activity)
                .environment(navigator)
        } label: {
            Image("MenuBarIcon")
                .accessibilityLabel("DotMD")
        }
        .menuBarExtraStyle(.menu)

        DocumentGroup(viewing: MarkdownFile.self) { configuration in
            ReaderScreen(text: configuration.document.text, fileURL: configuration.fileURL)
                .background(WindowTabbing())
                .frame(minWidth: 560, minHeight: 480)
                .environment(library)
                .environment(bridge)
                .environment(activity)
                .task { await AppServices.start() }
        }
        .commands { ExportCommands() }
    }
}
