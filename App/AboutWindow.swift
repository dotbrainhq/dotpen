import AppKit
import SwiftUI

/// dotPen > About dotPen: the icon on the brand gradient, the wordmark and tagline, a version line that copies itself
/// for bug reports, and the links people look for in an About window.
struct AboutView: View {
    @State private var copied = false

    private static let website = URL(string: "https://dotpen.app")!
    private static let privacy = URL(string: "https://dotpen.app/privacy")!
    private static let contact = URL(string: "https://dotbrainhq.com/contact")!

    var body: some View {
        VStack(spacing: 0) {
            Image("BrandIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                .padding(.top, 34)
                .accessibilityHidden(true)
            // The wordmark: "dot" in ink, as in Dotbrain's other names, and "Pen" in dotPen's green.
            (Text("dot").foregroundStyle(Palette.ink) + Text("Pen").foregroundStyle(Palette.accent))
                .font(.system(size: 30, weight: .heavy))
                .tracking(-0.6)
                .padding(.top, 18)
                .accessibilityLabel("dotPen")
            Text("Read what your agents write.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink3)
                .padding(.top, 4)
            Button(action: copyVersion) {
                Text(copied ? "Version info copied" : "Version \(Self.version)")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Palette.ink4)
                    .contentTransition(.opacity)
            }
            .buttonStyle(.plain)
            // The window would otherwise open with a focus ring on the version line.
            .focusEffectDisabled()
            .help("Copy the version for a bug report")
            .padding(.top, 10)
            HStack(spacing: 8) {
                AboutLink("Website") { NSWorkspace.shared.open(Self.website) }
                Dot()
                AboutLink("Privacy") { NSWorkspace.shared.open(Self.privacy) }
                Dot()
                AboutLink("Contact") { NSWorkspace.shared.open(Self.contact) }
                Dot()
                AboutLink("Acknowledgments", action: openAcknowledgments)
            }
            .padding(.top, 22)
            VStack(spacing: 2) {
                Text("Open source, and nothing leaves your Mac.")
                Text(Self.copyright)
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.ink4)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .frame(width: 340)
        .background {
            ZStack(alignment: .top) {
                Palette.window
                BrandBackdrop()
                    .frame(height: 230)
                    // Fades into the window so the gradient sits behind the icon only.
                    .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
        }
        .background {
            WindowButtons(closeCenter: CGPoint(x: 22, y: 20))
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private static var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "© Dotbrain LLC"
    }

    private func copyVersion() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("dotPen \(Self.version) on macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.15)) { copied = false }
        }
    }

    /// The licenses ship as Markdown in the app, so dotPen opens them in its own reader.
    private func openAcknowledgments() {
        guard let url = Bundle.main.url(forResource: "Acknowledgments", withExtension: "md") else { return }
        FileActions.openInNewWindow(url)
    }
}

private struct AboutLink: View {
    let title: String
    let action: () -> ()
    @State private var hovering = false

    init(_ title: String, action: @escaping () -> ()) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.accentInk)
            .underline(hovering)
            .onHover { hovering = $0 }
    }
}

private struct Dot: View {
    var body: some View {
        Circle()
            .fill(Palette.ink5)
            .frame(width: 3, height: 3)
            .accessibilityHidden(true)
    }
}

/// The spec's brand backdrop: a mesh of dotPen greens drifting over about 26 seconds. Reduce Motion holds it still.
struct BrandBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * (2 * .pi / 26)
            MeshGradient(width: 3, height: 3, points: points(phase), colors: colors)
        }
        .accessibilityHidden(true)
    }

    /// The corners stay put; the edge midpoints and the center drift on slow, offset circles.
    private func points(_ phase: Double) -> [SIMD2<Float>] {
        func drift(_ x: Double, _ y: Double, _ amount: Double, _ offset: Double) -> SIMD2<Float> {
            [Float(x + amount * cos(phase + offset)), Float(y + amount * sin(phase + offset))]
        }
        return [
            [0, 0], drift(0.5, 0, 0.12, 0).clampedY(0), [1, 0],
            drift(0, 0.5, 0.1, 1.7).clampedX(0), drift(0.5, 0.5, 0.14, 3.1), drift(1, 0.5, 0.1, 4.4).clampedX(1),
            [0, 1], drift(0.5, 1, 0.12, 5.2).clampedY(1), [1, 1],
        ]
    }

    private var colors: [Color] {
        colorScheme == .dark
            ? [.init(hex: 0x0B2A1E), .init(hex: 0x12402C), .init(hex: 0x0D3324),
               .init(hex: 0x15523A), .init(hex: 0x1F6B4A), .init(hex: 0x0F3A29),
               .init(hex: 0x0E2F22), .init(hex: 0x134531), .init(hex: 0x0B2A1E)]
            : [.init(hex: 0xE3F5EC), .init(hex: 0xC6ECD8), .init(hex: 0xE9F7F0),
               .init(hex: 0xB4E5CB), .init(hex: 0x8ED6B1), .init(hex: 0xCFEFDE),
               .init(hex: 0xEEF8F3), .init(hex: 0xD5F1E2), .init(hex: 0xE6F6EE)]
    }
}

private extension SIMD2 where Scalar == Float {
    func clampedX(_ value: Float) -> Self { [value, y] }
    func clampedY(_ value: Float) -> Self { [x, value] }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// dotPen > About dotPen opens the window above in place of the standard panel.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About dotPen") { openWindow(id: "about") }
        }
    }
}
