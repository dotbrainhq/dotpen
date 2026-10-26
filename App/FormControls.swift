import SwiftUI

/// The prototype's `.btn`: 30 points tall on a soft fill, or dotPen's green for the main action.
struct FormButtonStyle: ButtonStyle {
    var primary = false
    /// The prototype shrinks the button inline in places: 26 points in Settings rows, 24 for Done.
    var height: CGFloat = 30
    var horizontalPadding: CGFloat = 14
    var fontSize: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        FormButtonBody(label: configuration.label, style: self, pressed: configuration.isPressed)
    }
}

private struct FormButtonBody<Label: View>: View {
    let label: Label
    let style: FormButtonStyle
    let pressed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        label
            .font(.system(size: style.fontSize, weight: style.primary ? .semibold : .medium))
            .foregroundStyle(style.primary ? Palette.onAccent : Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, style.horizontalPadding)
            .frame(height: style.height)
            .background(style.primary ? Palette.accent : hovering ? Palette.fill2 : Palette.fill, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? (pressed ? 0.8 : 1) : 0.45)
            .onHover { hovering = $0 }
    }
}

/// A switch on its own, the prototype's `.sw`, for rows where the label sits apart from it.
struct SwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            SwitchMark(isOn: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// The prototype's `.sw`: a 28 by 16 point track with a 12 point knob.
struct SwitchMark: View {
    let isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(isOn ? Palette.accent : Palette.fill2)
            .frame(width: 28, height: 16)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .offset(x: isOn ? 14 : 2)
                    // Reduce Motion: the knob jumps and only the color fades.
                    .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.14), value: isOn)
            }
            .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.14), value: isOn)
    }
}
