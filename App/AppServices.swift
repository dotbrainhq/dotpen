import AppKit
import DotMDCore

/// The objects every window shares with the menu bar item, Shortcuts actions, Services and the command line.
@MainActor
enum AppServices {
    static let library = Library.makeDefault()
    static let bridge = AgentBridge(library: library)
    static let activity = AgentActivity(library: library)
    static let spotlight = SpotlightIndex(library: library)
    static let navigator = FilesNavigator()
    static let reviews = ReviewQueue(library: library)

    /// Loads the library and starts what depends on it. Every window, and every Shortcuts action, calls this;
    /// each part starts once.
    static func start() async {
        await library.start()
        bridge.startIfEnabled()
        activity.start()
        spotlight.update()
    }

    /// Files open in a document window; folders get watched. `dotmd <path>`, Finder's Open in DotMD service, and
    /// Spotlight's Open With all come through here.
    static func open(_ urls: [URL]) {
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                FileActions.watch(url, in: library)
            } else {
                FileActions.openInNewWindow(url)
            }
        }
    }
}

/// Hands opened files and folders to AppServices, and offers the Open in DotMD service.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = ServicesProvider()
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { AppServices.open(urls) }
    }
}

/// Finder's Services menu: Open in DotMD for Markdown files and folders.
final class ServicesProvider: NSObject {
    @objc func openInDotMD(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        MainActor.assumeIsolated { AppServices.open(urls) }
    }
}
