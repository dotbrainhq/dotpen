import DotPenCore
import SwiftUI

/// The prototype's `.cpanel`: the file's comments, open or resolved, with Send and Copy as Prompt at the bottom.
/// It sits on the right of the reader, under the bar.
struct CommentsPanel: View {
    let comments: [PlacedComment]
    /// Who Send goes to, like "Claude Code".
    let agent: String
    let onReveal: (PlacedComment) -> ()
    let onResolve: (Comment, Bool) -> ()
    let onSend: () -> ()
    let onCopyPrompt: () -> ()

    @State private var showResolved = false
    @State private var selected: Int64?

    private var open: [PlacedComment] { comments.filter { $0.comment.status == .open } }
    private var resolved: [PlacedComment] { comments.filter { $0.comment.status == .resolved } }
    private var inPrompt: Int { open.filter(\.comment.isInPrompt).count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Comments")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                TwoSegments(first: "Open \(open.count)", second: "Resolved \(resolved.count)", showsSecond: $showResolved)
            }
            .padding(EdgeInsets(top: 14, leading: 14, bottom: 10, trailing: 14))
            let items = showResolved ? resolved : open
            if items.isEmpty {
                Text(showResolved ? "No resolved comments." : "No open comments. Select text on the page and press C to comment.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink4)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(items) { item in
                            PanelItem(item: item, isSelected: selected == item.id, onResolve: onResolve)
                                .onTapGesture {
                                    selected = item.id
                                    onReveal(item)
                                }
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            footer
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(Palette.window)
        .overlay(alignment: .leading) {
            Palette.line.frame(width: 0.5)
        }
    }

    /// The prototype's `.cp-f`: Send fills the row, Copy as Prompt sits beside it as an icon.
    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onSend) {
                HStack(spacing: 6) {
                    Text(inPrompt > 0 ? "Send \(inPrompt) to \(agent)" : "Send to agent")
                    Text("⌘↩")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.75)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(FormButtonStyle(primary: true))
            .disabled(inPrompt == 0)
            // The prototype spells this out, which pushes it past the panel's edge beside "Send 1 to Claude Code".
            Button(action: onCopyPrompt) {
                Icon("copy", size: 16)
            }
            .buttonStyle(FormButtonStyle(horizontalPadding: 7))
            .disabled(inPrompt == 0)
            .help("Copy as Prompt")
            .accessibilityLabel("Copy as Prompt")
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .overlay(alignment: .top) {
            Palette.line.frame(height: 0.5)
        }
    }
}

/// The prototype's `.cp-item`: the passage, the comment, and who wrote it when, with Resolve or Reopen.
private struct PanelItem: View {
    let item: PlacedComment
    let isSelected: Bool
    let onResolve: (Comment, Bool) -> ()

    private var comment: Comment { item.comment }
    private var done: Bool { comment.status == .resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(comment.quote)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(Palette.ink3)
                .lineSpacing(3)
                .lineLimit(3)
                .padding(.leading, 9)
                .overlay(alignment: .leading) {
                    (done ? Palette.ink5 : Palette.accent).frame(width: 2)
                }
                .padding(.bottom, 6)
            Text(comment.body)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .padding(.bottom, 8)
            HStack {
                Text(meta)
                Spacer(minLength: 8)
                Button(done ? "Reopen" : "Resolve") { onResolve(comment, !done) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accentInk)
                    .fontWeight(.medium)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(isSelected ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Palette.accentLine : Palette.line, lineWidth: isSelected ? 1.5 : 0.5)
        }
        .opacity(done ? 0.6 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    /// "You · 2:20 PM · line 14", or "Resolved · sent at 1:40 PM".
    private var meta: String {
        if done {
            guard let sentAt = comment.sentAt else { return "Resolved" }
            return "Resolved · " + Self.sent(sentAt)
        }
        let place = item.range.map { "line \($0.start)" } ?? "passage changed"
        return "You · \(ReadingLabels.commentTime(comment.createdAt)) · \(place)"
    }

    private static func sent(_ date: Date) -> String {
        let time = ReadingLabels.commentTime(date)
        if time == "now" { return "sent just now" }
        return time.first?.isNumber == true ? "sent at \(time)" : "sent \(time)"
    }
}

/// The prototype's `.seg3.two`: two equal segments on a soft fill, the chosen one raised.
private struct TwoSegments: View {
    let first: String
    let second: String
    @Binding var showsSecond: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            segment(first, isOn: !showsSecond) { showsSecond = false }
            segment(second, isOn: showsSecond) { showsSecond = true }
        }
        .padding(2)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 8))
    }

    private func segment(_ title: String, isOn: Bool, action: @escaping () -> ()) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isOn ? .medium : .regular))
                .foregroundStyle(isOn ? Palette.ink : Palette.ink2)
                .lineLimit(1)
                .padding(.vertical, 4)
                .frame(width: 73)
                .background {
                    if isOn {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Palette.raised)
                            .modifier(ShadowOne(shape: RoundedRectangle(cornerRadius: 6), fill: Palette.raised, dark: colorScheme == .dark))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
