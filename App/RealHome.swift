import Foundation

enum RealHome {
    /// The person's home folder. NSHomeDirectory points inside the sandbox container, so this reads the user record.
    static let path: String = {
        #if DEBUG
        // `-DotMDDemoHome <path>` stands in for the home folder, so prototype checks read ~/code like the mockup.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-DotMDDemoHome"), index + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL.path
        }
        #endif
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return NSHomeDirectory() }
        return String(cString: directory)
    }()

    /// "~/code/api" for a folder in the home folder, the full path otherwise.
    static func abbreviate(_ url: URL) -> String {
        let full = url.path
        if full == path { return "~" }
        return full.hasPrefix(path + "/") ? "~" + full.dropFirst(path.count) : full
    }
}
