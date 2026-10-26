import DotPenCore
import SwiftUI

/// The frame every outline row shares, the prototype's `.tr`: 28 points tall, indented 14 points per level,
/// a soft fill on hover, the green wash when selected, and a 2 point ring while it has keyboard focus.
struct OutlineRowChrome: ViewModifier {
    let depth: Int
    var selected = false
    var focused = false
    var topMargin: CGFloat = 0
    @State private var hovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        content
            .padding(.leading, 8 + CGFloat(depth) * 14)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
            .background(selected ? Palette.selection : hovering ? Palette.fill : .clear, in: shape)
            .overlay {
                if focused {
                    // Inside the row's edge, like the prototype's 2px outline at -2px offset.
                    shape.strokeBorder(Palette.accent, lineWidth: 2)
                }
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .padding(.top, topMargin)
    }
}

/// The disclosure chevron's 10 point slot. Rows that can't open keep the empty slot so names line up.
struct Twisty: View {
    let isExpanded: Bool?

    var body: some View {
        ZStack {
            if let isExpanded {
                Icon("chevron", size: 10)
                    .foregroundStyle(Palette.ink4)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

struct FolderRow: View {
    let folder: FolderState
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 6) {
            Twisty(isExpanded: isExpanded)
            Icon("folder", size: 16)
                .foregroundStyle(folder.folder.color.color)
            Text(folder.folder.name)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
            if let branch = folder.branch {
                // Clipped at the badge with no ellipsis, as the prototype draws "feat/rate-".
                HStack(spacing: 3) {
                    Icon("branch", size: 11)
                    Text(branch)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(Palette.ink4)
                .padding(.leading, 6)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()
            } else {
                Spacer(minLength: 0)
            }
            if folder.unreadCount > 0 && !folder.accessLost {
                Text("\(folder.unreadCount)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 16, maxHeight: 16)
                    .background(Palette.fill2, in: Capsule())
                    .fixedSize()
                    .transition(.opacity)
            }
            if folder.accessLost {
                Icon("warn", size: 14)
                    .foregroundStyle(Palette.warn)
            }
        }
        .foregroundStyle(Palette.ink)
        .animation(.easeOut(duration: 0.15), value: folder.unreadCount > 0 && !folder.accessLost)
        .help(folder.accessLost ? "dotPen lost access to this folder. Right-click to choose it again." : folder.folder.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(folder.folder.name)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts = [isExpanded ? "Expanded" : "Collapsed"]
        if folder.accessLost {
            parts.append("Access lost")
        } else if folder.unreadCount > 0 {
            parts.append("\(folder.unreadCount) unread")
        }
        if let branch = folder.branch { parts.append("Branch \(branch)") }
        return parts.joined(separator: ", ")
    }
}

/// A subfolder that holds Markdown, named by its path inside the watched folder, for example "docs/plans".
struct DirectoryRow: View {
    let path: String
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 6) {
            Twisty(isExpanded: isExpanded)
            Icon("directory", size: 15)
                .foregroundStyle(Palette.ink4)
            Text(path)
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(path)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

struct FileRow: View {
    let document: DotPenCore.Document
    let showTitles: Bool
    let depth: Int
    let selected: Bool
    let focused: Bool
    @Environment(Library.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isWriting: Bool { library.writing.contains(document.key) }
    /// An agent asked for the person's review of this file and is waiting.
    private var awaitsReview: Bool { AppServices.reviews.pending(for: document.key) != nil }

    var body: some View {
        // The row frame goes on first so dragging and the menu work across the whole row, padding included.
        draggable(content.modifier(OutlineRowChrome(depth: depth, selected: selected, focused: focused)))
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
            Twisty(isExpanded: nil)
            Icon(document.kind.iconName, size: 15)
                .foregroundStyle(Palette.accentInk)
                .opacity(selected ? 1 : 0.85)
            Text(document.displayName(showTitles: showTitles))
                .font(.system(size: 13, weight: document.readState == .read ? .regular : .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            if document.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.ink4)
            }
            Spacer(minLength: 0)
            badge
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.85), value: badgeState)
        .help(showTitles ? document.relativePath : (document.title ?? document.relativePath))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(document.displayName(showTitles: showTitles))
        .accessibilityValue(accessibilityValue)
    }

    /// The pencil while the file is being written wins, then an amber dot while an agent waits for review, then the
    /// unread dot.
    @ViewBuilder private var badge: some View {
        if isWriting {
            Icon("pencil", size: 13)
                .foregroundStyle(Palette.accent)
                .symbolEffect(.wiggle, options: .repeating.speed(0.5), isActive: !reduceMotion)
                .frame(width: 16, height: 16)
                .transition(.opacity)
        } else if awaitsReview {
            Circle()
                .fill(Palette.warn)
                .frame(width: 7, height: 7)
                .help("An agent is waiting for your review")
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        } else if document.readState != .read {
            Circle()
                .fill(Palette.accent)
                .frame(width: 7, height: 7)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        }
    }

    /// Drives the badge animation: 0 read, 1 unread, 2 being written, 3 waiting for review.
    private var badgeState: Int {
        isWriting ? 2 : awaitsReview ? 3 : document.readState == .read ? 0 : 1
    }

    private var accessibilityValue: String {
        if isWriting { return "Being written" }
        if awaitsReview { return "Waiting for your review" }
        switch document.readState {
        case .read: return ""
        case .new: return "New"
        case .changed: return "Changed since you read it"
        }
    }
}

/// "Hiding node_modules, build and 214 paths in .gitignore Show", once at the end of the outline.
struct HiddenPathsNote: View {
    @Environment(Library.self) private var library

    var body: some View {
        if let summary = HiddenPathsSummary.text(for: library.folders, showIgnored: library.showIgnored) {
            Text(sentence(summary))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink4)
                .lineSpacing(3)
                .tint(Palette.accentInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                .environment(\.openURL, OpenURLAction { _ in
                    library.showIgnored.toggle()
                    return .handled
                })
        }
    }

    /// The summary with the Show or Hide link inline, so it wraps with the sentence as in the prototype.
    private func sentence(_ summary: String) -> AttributedString {
        var text = AttributedString(summary + " ")
        var link = AttributedString(library.showIgnored ? "Hide" : "Show")
        link.link = URL(string: "dotpen-action:toggle-hidden-paths")
        link.font = .system(size: 11.5, weight: .medium)
        link.foregroundColor = Palette.accentInk
        link.underlineStyle = nil
        text.append(link)
        return text
    }
}
