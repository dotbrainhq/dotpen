import SwiftUI

/// The prototype's `.arrive`, under the bar in the document layout: an agent just wrote a new file elsewhere.
struct ArrivalBanner: View {
    let agent: String
    let file: String
    let folder: String
    let onOpen: () -> ()
    let onDismiss: () -> ()

    var body: some View {
        HStack(spacing: 10) {
            LiveDot()
            (Text(agent).fontWeight(.semibold).foregroundStyle(Palette.ink)
                + Text(" just wrote ")
                + Text(file).fontWeight(.semibold).foregroundStyle(Palette.ink)
                + Text(" in \(folder)"))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Open", action: onOpen)
                .buttonStyle(BannerButtonStyle(tint: Palette.accentInk, weight: .semibold, horizontal: 8))
            Button(action: onDismiss) {
                Text("✕")
            }
            .buttonStyle(BannerButtonStyle(tint: Palette.ink4, weight: .regular, horizontal: 6))
            .accessibilityLabel("Dismiss")
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Palette.ink2)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 36)
        .background(Palette.accentWash, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }
}

/// `.arrive .go` and `.arrive .x`: text buttons with a soft fill under the pointer.
private struct BannerButtonStyle: ButtonStyle {
    let tint: Color
    let weight: Font.Weight
    let horizontal: CGFloat
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(weight)
            .foregroundStyle(tint)
            .padding(.vertical, 4)
            .padding(.horizontal, horizontal)
            .background(hovering ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { hovering = $0 }
    }
}

/// The prototype's `.follow`: an agent is writing this file, and the view keeps its newest block in sight.
struct FollowingPill: View {
    let agent: String
    let following: Bool
    let onToggle: () -> ()

    var body: some View {
        HStack(spacing: 10) {
            LiveDot()
            Text("\(agent) is writing").fontWeight(.semibold).foregroundStyle(Palette.ink)
            Text(following ? "Following along" : "Not following").foregroundStyle(Palette.ink3)
            // F toggles it too; the page sends that, so typing an f in a comment doesn't.
            Button(following ? "Stop following" : "Follow", action: onToggle)
                .buttonStyle(PillButtonStyle(primary: false))
        }
        .modifier(PillChrome(leading: 14))
    }
}

/// The prototype's `.donepill`: the agent stopped writing this file. Review Changes goes to the first change.
struct FinishedPill: View {
    let agent: String
    let changes: Int
    let onReview: () -> ()
    let onDismiss: () -> ()

    var body: some View {
        HStack(spacing: 10) {
            Icon("check", size: 16).foregroundStyle(Palette.accent)
            Text("\(agent) finished").fontWeight(.semibold).foregroundStyle(Palette.ink)
            if changes > 0 {
                Text(changes == 1 ? "1 change since you read" : "\(changes) changes since you read").foregroundStyle(Palette.ink3)
                Button("Review Changes", action: onReview)
                    .buttonStyle(PillButtonStyle(primary: true))
            } else {
                Button("Done", action: onDismiss)
                    .buttonStyle(PillButtonStyle(primary: false))
            }
        }
        .modifier(PillChrome(leading: 12))
    }
}

/// The pills' 26 point buttons: a soft fill, or DotMD's green for Review Changes.
private struct PillButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: primary ? .semibold : .medium))
            .foregroundStyle(primary ? Palette.onAccent : Palette.ink)
            .padding(.horizontal, primary ? 11 : 10)
            .frame(height: 26)
            .background(primary ? Palette.accent : Palette.fill, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// 36 points tall on glass, 18 above the bottom edge, with the prototype's `--shadow-2`.
private struct PillChrome: ViewModifier {
    let leading: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12.5))
            .lineLimit(1)
            .padding(.leading, leading)
            .padding(.trailing, 6)
            .frame(height: 36)
            .background(Palette.glass, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.glassEdge, lineWidth: 0.5))
            .background {
                Capsule()
                    .fill(Palette.glass)
                    .padding(10)
                    .shadow(color: colorScheme == .dark ? .black.opacity(0.6) : Color(red: 3 / 255, green: 26 / 255, blue: 27 / 255).opacity(0.28),
                            radius: 15, y: 10)
            }
            .padding(.bottom, 18)
            .accessibilityElement(children: .contain)
    }
}
