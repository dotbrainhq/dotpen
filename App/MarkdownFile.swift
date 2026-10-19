import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist as an imported type so DotMD opens .md, .markdown and .mdown files.
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct MarkdownFile: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown, .plainText]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
