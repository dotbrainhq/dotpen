import SwiftUI

/// What the Files window tells the reader inside it: whether the file list is showing, and how to toggle it.
/// Present only in the Files window; a document window has none and keeps the system toolbar.
struct FilesChrome {
    let sidebarVisible: Bool
    let toggleSidebar: () -> ()
    /// Shows a sheet over the whole window, as the prototype's Send sheet is, or takes it away when nil.
    let showSheet: (AnyView?) -> ()
    /// Shows the palette or the keyboard shortcuts over the whole window.
    let showOverlay: (WindowOverlay) -> ()
}

extension EnvironmentValues {
    @Entry var filesChrome: FilesChrome?
    /// Whether caps sit on the document layout's tinted bar rather than the window background.
    @Entry var capsOnBar = false
}

/// The Files window's 52 point bar over the document, the prototype's `.tbar`: the sidebar button, the centered
/// title block, then the caps passed in. With the file list hidden it leaves room for the window buttons on its left.
struct TopBar<Trailing: View>: View {
    let chrome: FilesChrome
    let title: String
    let path: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            if !chrome.sidebarVisible {
                // The window buttons: three 12 point dots 8 apart, then the prototype's 6 point margin.
                Color.clear.frame(width: 52 + 6, height: 12)
            }
            Cap {
                Button(action: chrome.toggleSidebar) {
                    Icon("sidebar", size: 16)
                }
                .buttonStyle(CapButtonStyle())
                .help(chrome.sidebarVisible ? "Hide the file list ⌥⌘S" : "Show the file list ⌥⌘S")
                .accessibilityLabel(chrome.sidebarVisible ? "Hide the file list" : "Show the file list")
            }
            TitleBlock(title: title, path: path)
                .frame(maxWidth: .infinity)
            trailing
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 52)
        .environment(\.capsOnBar, !chrome.sidebarVisible)
        .background {
            // Dragging the bar's empty space moves the window, as a title bar would. Only the document layout tints it.
            (chrome.sidebarVisible ? Palette.window : Palette.bar)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }
}

/// Two centered lines, the prototype's `.ttl`: the title at 13 points semibold, the path at 11 points monospaced.
struct TitleBlock: View {
    let title: String
    let path: String

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
            if !path.isEmpty {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.ink4)
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .accessibilityElement(children: .combine)
    }
}

/// A glass pill that holds one or more toolbar buttons, the prototype's `.cap`.
struct Cap<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.capsOnBar) private var onBar

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        // The system's focus ring lands on the first cap when the window opens; the prototype draws none.
        .focusEffectDisabled()
        .padding(.horizontal, 3)
        .frame(height: 32)
        .background(onBar ? Palette.glassOnBar : Palette.glass, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.glassEdge, lineWidth: 0.5))
        .modifier(ShadowOne(shape: Capsule(), fill: onBar ? Palette.glassOnBar : Palette.glass, dark: colorScheme == .dark))
    }
}

/// The prototype's `--shadow-1`: two soft one-point drops in light mode, one deeper one in dark mode. Each drop is
/// cast by its own copy of the shape, as CSS casts each shadow from the box: chained SwiftUI shadows would compound.
struct ShadowOne<S: Shape>: ViewModifier {
    let shape: S
    /// The surface's own color, so the shadow casters never show at its anti-aliased edge.
    let fill: Color
    let dark: Bool

    func body(content: Content) -> some View {
        content.background {
            if dark {
                shape.fill(fill).shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            } else {
                let tint = Color(red: 10 / 255, green: 25 / 255, blue: 26 / 255)
                ZStack {
                    shape.fill(fill).shadow(color: tint.opacity(0.06), radius: 0.5, y: 1)
                    shape.fill(fill).shadow(color: tint.opacity(0.06), radius: 1.5, y: 1)
                }
            }
        }
    }
}

/// A button inside a cap: 26 points tall, at least 30 wide, 9 points of side padding, ink-2, and a fill under the pointer.
/// The prototype's `.cap.send` button keeps its green on hover and is semibold.
struct CapButtonStyle: ButtonStyle {
    var tint: Color?
    var weight: Font.Weight = .medium

    func makeBody(configuration: Configuration) -> some View {
        CapButtonBody(label: configuration.label, pressed: configuration.isPressed, tint: tint, weight: weight)
    }
}

private struct CapButtonBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    let tint: Color?
    let weight: Font.Weight
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        label
            .font(.system(size: 12.5, weight: isEnabled ? weight : .medium))
            // Disabled, the prototype's send button goes ink-4 and stops reacting to the pointer.
            .foregroundStyle(!isEnabled ? Palette.ink4 : tint ?? (hovering ? Palette.ink : Palette.ink2))
            .padding(.horizontal, 9)
            .frame(minWidth: 30, minHeight: 26, maxHeight: 26)
            .background(hovering && isEnabled ? Palette.fill : .clear, in: Capsule())
            .contentShape(Capsule())
            .opacity(pressed ? 0.7 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// The prototype's `.count`: how many comments the next Send carries, on dotPen's green.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 5)
            .frame(minWidth: 17, minHeight: 17)
            .background(Palette.accent, in: Capsule())
    }
}
