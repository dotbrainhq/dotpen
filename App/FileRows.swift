import DotMDCore
import SwiftUI

struct FolderRow: View {
    let folder: FolderState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: folder.accessLost ? "lock.fill" : "folder.fill")
                .foregroundStyle(folder.folder.color.color)
            Text(folder.folder.name)
                .fontWeight(.semibold)
                .lineLimit(1)
            if let branch = folder.branch {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if folder.unreadCount > 0 {
                Text("\(folder.unreadCount)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(.quaternary, in: Capsule())
            }
        }
        .opacity(folder.accessLost ? 0.6 : 1)
        .help(folder.accessLost ? "DotMD lost access to this folder. Right-click to choose it again." : folder.folder.path)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if folder.accessLost { return "Access lost" }
        return folder.unreadCount > 0 ? "\(folder.unreadCount) unread" : ""
    }
}

struct FileRow: View {
    let document: DotMDCore.Document
    let showTitles: Bool
    @Environment(Library.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isWriting: Bool { library.writing.contains(document.key) }

    var body: some View {
        draggable(content)
            .contextMenu { FileMenu(document: document) }
    }

    /// Drag the file out to Finder or another app, when the library has its location.
    @ViewBuilder private func draggable(_ content: some View) -> some View {
        if let url = library.url(for: document) {
            content.draggable(url)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            Image(systemName: document.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(document.displayName(showTitles: showTitles))
                .lineLimit(1)
                .truncationMode(.middle)
            if document.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            badge
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.85), value: badgeState)
        .help(showTitles ? document.relativePath : (document.title ?? document.relativePath))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(document.displayName(showTitles: showTitles))
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder private var badge: some View {
        if isWriting {
            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.wiggle, options: .repeating.speed(0.5), isActive: !reduceMotion)
                .transition(.opacity)
        } else if document.readState != .read {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 7, height: 7)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
    }

    /// Drives the badge animation: 0 read, 1 unread, 2 being written.
    private var badgeState: Int {
        isWriting ? 2 : document.readState == .read ? 0 : 1
    }

    private var accessibilityValue: String {
        if isWriting { return "Being written" }
        switch document.readState {
        case .read: return ""
        case .new: return "New"
        case .changed: return "Changed since you read it"
        }
    }
}

/// "Hiding node_modules, build and 12 more." at the end of a folder, with a way to show them.
struct IgnoredNote: View {
    @Environment(Library.self) private var library
    let ignored: [String]

    var body: some View {
        HStack(spacing: 4) {
            Text(library.showIgnored ? "Showing ignored paths." : summary)
            Button(library.showIgnored ? "Hide" : "Show") { library.showIgnored.toggle() }
                .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var summary: String {
        let names = ignored.prefix(2).map { ($0 as NSString).lastPathComponent }
        let rest = ignored.count - names.count
        let list = names.joined(separator: ", ")
        return rest > 0 ? "Hiding \(list) and \(rest) more." : "Hiding \(list)."
    }
}
