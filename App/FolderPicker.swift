import AppKit

enum FolderPicker {
    /// Asks for one folder with the standard open panel. Returns nil when the person cancels.
    @MainActor
    /// showsHidden lets the panel show folders like ~/.claude, where agents keep their logs.
    static func chooseFolder(message: String, prompt: String = "Watch", startingAt directory: URL? = nil, showsHidden: Bool = false) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = message
        panel.prompt = prompt
        panel.directoryURL = directory
        panel.showsHiddenFiles = showsHidden
        return panel.runModal() == .OK ? panel.url : nil
    }
}
