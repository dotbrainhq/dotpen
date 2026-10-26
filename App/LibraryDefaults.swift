import DotPenCore
import SwiftUI

extension Library {
    /// The library in the app container. If that database can't be created the app still opens files,
    /// with a library that lasts until quit.
    static func makeDefault() -> Library {
        let url = URL.applicationSupportDirectory.appending(path: "dotPen/library.sqlite")
        if let database = try? LibraryDatabase.open(at: url) {
            return Library(database: database)
        }
        // An in-memory database only fails when SQLite itself can't start.
        return Library(database: try! LibraryDatabase.inMemory())
    }
}

extension FolderColor {
    /// The prototype's muted folder colors (oklch at about 66% lightness), not the saturated system colors.
    var color: Color {
        switch self {
        case .blue: Color(red: 84 / 255, green: 151 / 255, blue: 217 / 255)
        case .orange: Color(red: 227 / 255, green: 141 / 255, blue: 61 / 255)
        case .purple: Color(red: 146 / 255, green: 116 / 255, blue: 195 / 255)
        case .pink: Color(red: 204 / 255, green: 111 / 255, blue: 157 / 255)
        case .red: Color(red: 205 / 255, green: 96 / 255, blue: 90 / 255)
        case .yellow: Color(red: 222 / 255, green: 186 / 255, blue: 80 / 255)
        case .indigo: Color(red: 102 / 255, green: 115 / 255, blue: 193 / 255)
        case .gray: Color(red: 136 / 255, green: 141 / 255, blue: 146 / 255)
        }
    }

    var name: String { rawValue.capitalized }
}
