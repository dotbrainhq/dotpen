import AppKit

enum FolderPicker {
    /// Asks for one folder with the standard open panel. Returns nil when the person cancels.
    @MainActor
    static func chooseFolder(message: String, prompt: String = "Watch", startingAt directory: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = message
        panel.prompt = prompt
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }
}
