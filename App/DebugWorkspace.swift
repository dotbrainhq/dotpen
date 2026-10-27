#if DEBUG
import DotPenCore
import Foundation

/// Debug builds only: `-DotPenDemoWorkspace <path>` watches each folder directly inside path, for side-by-side
/// checks against the prototype. The path sits in the app's container, so the sandbox allows it.
enum DebugWorkspace {
    @MainActor static func open(in library: Library) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-DotPenDemoWorkspace"), index + 1 < arguments.count else { return }
        let root = URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath, isDirectory: true)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        let folders = children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for folder in folders {
            // addFolder skips a folder already watched at the same path.
            try? await library.addFolder(folder)
        }
    }
}
#endif
