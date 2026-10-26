import CoreSpotlight
import DotMDCore
import Foundation
import Observation
import UniformTypeIdentifiers

/// Puts watched files in Spotlight by title, headings and text, so a search there opens them in dotPen. On by
/// default, as in the prototype's Integrations pane; the switch there removes everything dotPen added.
@MainActor
@Observable
final class SpotlightIndex {
    private(set) var isEnabled: Bool
    private let library: Library
    private let index = CSSearchableIndex(name: "dotPen")
    /// What Spotlight has, by file path: the content hash it was indexed at.
    private var indexed: [String: String] = [:]
    private var pending: Task<(), Never>?
    private static let enabledKey = "spotlightEnabled"

    /// Spotlight gets the start of each file; long logs and specs don't need more to be found.
    nonisolated static let textLimit = 20_000

    init(library: Library) {
        self.library = library
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            update()
        } else {
            pending?.cancel()
            indexed = [:]
            index.deleteAllSearchableItems { _ in }
        }
    }

    /// Indexes what changed since the last pass, two seconds after the last change, and drops files that went.
    func update() {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.indexChanges()
        }
    }

    /// The file a Spotlight result names, from the item's identifier.
    static func fileURL(fromIdentifier identifier: String) -> URL {
        URL(fileURLWithPath: identifier)
    }

    private func indexChanges() async {
        var current: [String: (document: DotMDCore.Document, url: URL, folder: String)] = [:]
        for folder in library.folders {
            for document in folder.documents {
                guard let url = library.url(for: document) else { continue }
                current[url.path] = (document, url, folder.folder.name)
            }
        }
        let changed = current.filter { indexed[$0.key] != $0.value.document.contentHash }.map(\.value)
        let gone = indexed.keys.filter { current[$0] == nil }
        // Files are read off the main thread; the items, which aren't Sendable, are made back here.
        let texts = await Task.detached {
            changed.map { entry in (try? Data(contentsOf: entry.url)).map { String(decoding: $0.prefix(Self.textLimit), as: UTF8.self) } }
        }.value
        guard !Task.isCancelled, isEnabled else { return }
        // The first pass after launch starts clean, so files removed while dotPen was closed leave Spotlight too.
        if indexed.isEmpty { try? await index.deleteAllSearchableItems() }
        let items = zip(changed, texts).compactMap { entry, text in
            text.map { Self.item(for: entry.document, url: entry.url, folder: entry.folder, text: $0) }
        }
        if !items.isEmpty { try? await index.indexSearchableItems(items) }
        if !gone.isEmpty { try? await index.deleteSearchableItems(withIdentifiers: gone) }
        for entry in changed { indexed[entry.url.path] = entry.document.contentHash }
        for path in gone { indexed[path] = nil }
    }

    static func item(for document: DotMDCore.Document, url: URL, folder: String, text: String) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText))
        attributes.title = document.title ?? url.lastPathComponent
        attributes.displayName = attributes.title
        let body = MarkdownBlocks.blankingFrontMatter(text).trimmingCharacters(in: .whitespacesAndNewlines)
        attributes.contentDescription = "\(folder) · \(document.relativePath)"
        attributes.textContent = body
        attributes.keywords = DocumentHeadings.headings(in: text).map(\.title) + [folder]
        attributes.contentModificationDate = document.modifiedAt
        attributes.contentURL = url
        return CSSearchableItem(uniqueIdentifier: url.path, domainIdentifier: folder, attributeSet: attributes)
    }
}
