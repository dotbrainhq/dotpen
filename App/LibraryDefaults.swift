import DotMDCore
import SwiftUI

extension Library {
    /// The library in the app container. If that database can't be created the app still opens files,
    /// with a library that lasts until quit.
    static func makeDefault() -> Library {
        let url = URL.applicationSupportDirectory.appending(path: "DotMD/library.sqlite")
        if let database = try? LibraryDatabase.open(at: url) {
            return Library(database: database)
        }
        // An in-memory database only fails when SQLite itself can't start.
        return Library(database: try! LibraryDatabase.inMemory())
    }
}

extension FolderColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .gray: .gray
        }
    }

    var name: String { rawValue.capitalized }
}
