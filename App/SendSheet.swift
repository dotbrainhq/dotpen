import DotMDCore
import SwiftUI

/// The prototype's Send sheet: the prompt dotPen builds from the comments, two switches, and Copy prompt or Send.
/// Send copies the prompt too, so it works whether or not the agent reads comments through the bridge.
struct SendSheet: View {
    /// Who the comments go to, like "Claude Code".
    let agent: String
    /// "Connected to Claude Code in api-gateway" when that agent's session in this folder reads the bridge.
    let connectedTo: String?
    /// The file's path in its repository, where the agent works.
    let path: String
    /// What the prompt's last line calls the file, like "plan".
    let noun: String
    let items: [PromptBuilder.Item]
    /// What changed since the person last read the file, one line each. Empty hides the switch.
    let changeNotes: [String]
    let onCopy: (String) -> ()
    let onSend: (_ prompt: String, _ resolve: Bool) -> ()
    let onClose: () -> ()

    @Environment(AgentBridge.self) private var bridge
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("sendIncludesChanges") private var includeChanges = true
    @AppStorage("sendResolves") private var resolveAfter = false

    private var prompt: String {
        PromptBuilder.prompt(path: path, noun: noun, items: items, changeNotes: includeChanges ? changeNotes : [])
    }


    private var title: String {
        "Send \(items.count == 1 ? "1 comment" : "\(items.count) comments") to \(agent)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Icon("send", size: 16)
                Text(title)
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Palette.ink)
            .padding(.vertical, 1.5)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
            Text("dotPen turns your comments into a prompt with the exact lines they point at.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink3)
                .padding(.bottom, 14)
            PromptPreview(prompt: prompt)
            HStack(spacing: 18) {
                if !changeNotes.isEmpty {
                    Toggle("Include what changed since I read it", isOn: $includeChanges)
                }
                Toggle("Resolve comments after sending", isOn: $resolveAfter)
            }
            .toggleStyle(LabeledSwitchStyle())
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.ink2)
            .padding(.top, 14)
            .padding(.bottom, 16)
            HStack(spacing: 8) {
                destination
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { onCopy(prompt) } label: {
                    HStack(spacing: 6) {
                        Icon("copy", size: 16)
                        Text("Copy prompt")
                    }
                }
                .buttonStyle(FormButtonStyle())
                Button { onSend(prompt, resolveAfter) } label: {
                    HStack(spacing: 6) {
                        Text("Send")
                        Text("⌘↩")
                            .font(.system(size: 11, weight: .medium))
                            .opacity(0.75)
                    }
                }
                .buttonStyle(FormButtonStyle(primary: true))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(EdgeInsets(top: 22, leading: 24, bottom: 18, trailing: 24))
        .frame(width: 600)
        .background(Palette.raised, in: Self.shape)
        .modifier(ShadowThree(shape: Self.shape, fill: Palette.raised, dark: colorScheme == .dark))
        .background {
            // Escape closes the sheet, as it would a system sheet.
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Send to agent")
    }

    /// Hangs from the bar: square on top, 16 point corners below.
    private static let shape = UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)

    /// The prototype's `.dest`: where the comments go, with the live dot once an agent reads them over the bridge.
    @ViewBuilder private var destination: some View {
        HStack(spacing: 8) {
            switch bridge.state {
            case .running where connectedTo != nil:
                LiveDot()
                Text(connectedTo ?? "")
            case .running where bridge.lastAgent != nil:
                LiveDot()
                Text("\(bridge.lastAgent ?? agent) can read these through the bridge")
            case .running, .starting:
                Text("The bridge is on. No agent has connected yet.")
            case .off, .failed:
                Text("Send copies the prompt to paste into your agent.")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Palette.ink3)
        .lineLimit(1)
    }
}

/// The prototype's `.prompt`: monospaced on the code color, the first and last lines quiet and the passages green.
private struct PromptPreview: View {
    let prompt: String

    var body: some View {
        ScrollView {
            Text(styled)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.ink2)
                // The prototype's 1.6 line height.
                .lineSpacing(4.9)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.codeBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line, lineWidth: 0.5)
        }
    }

    private var styled: AttributedString {
        let lines = prompt.components(separatedBy: "\n")
        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            var piece = AttributedString(line)
            if index == 0 || index == lines.count - 1 {
                piece.foregroundColor = Palette.ink4
            } else if line.first?.isNumber == true, let quote = line.firstIndex(of: "\"") {
                var head = AttributedString(line[..<quote])
                var passage = AttributedString(line[quote...])
                head.foregroundColor = nil
                passage.foregroundColor = Palette.accentInk
                piece = head + passage
            }
            result += piece
            if index < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }
}

/// The prototype's `.opt`: a switch with its label beside it, both clickable.
private struct LabeledSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                SwitchMark(isOn: configuration.isOn)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// The prototype's `.live`: dotPen's green dot with a ring that grows and fades, still when motion is reduced.
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Palette.accent)
            .frame(width: 8, height: 8)
            .overlay {
                if !reduceMotion {
                    Circle()
                        .strokeBorder(Palette.accent, lineWidth: 1.5)
                        .padding(-3)
                        .scaleEffect(pulsing ? 1.6 : 0.6)
                        .opacity(pulsing ? 0 : 0.7)
                        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.8).repeatForever(autoreverses: false), value: pulsing)
                }
            }
            .onAppear { pulsing = true }
            .accessibilityHidden(true)
    }
}

/// The prototype's `--shadow-3`: a half point ring just outside the edge, and a long soft drop pulled in 20 points
/// on every side, as CSS's negative spread does.
struct ShadowThree<S: Shape>: ViewModifier {
    let shape: S
    let fill: Color
    let dark: Bool

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(dark ? Color.white.opacity(0.1) : Color.black.opacity(0.16))
                    .padding(-0.5)
            }
            .background {
                shape
                    .fill(fill)
                    .padding(20)
                    .shadow(color: dark ? .black.opacity(0.7) : Color(red: 0, green: 21 / 255, blue: 23 / 255).opacity(0.45), radius: 35, y: 30)
            }
    }
}
