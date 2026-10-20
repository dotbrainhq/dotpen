import AppKit
import DotMDCore
import SwiftUI

/// A code folder and what first launch found in it.
struct FolderSearch {
    let codeFolder: URL
    let candidates: [AgentFolderCandidate]

    var suggestedCount: Int { candidates.filter(\.isSuggested).count }
}

/// The prototype's `.first`, over the whole Files window until a folder is watched. It asks for the code folder,
/// then lists the projects inside it that agents write in, each with a switch.
struct FirstLaunchView: View {
    @Environment(Library.self) private var library
    @State private var search: FolderSearch?
    @State private var selected: Set<String> = []
    @State private var isSearching = false
    @State private var isAdding = false

    var body: some View {
        VStack(spacing: 0) {
            // The prototype's 52 point bar, which holds only the window buttons.
            Color.clear
                .frame(height: 52)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
            GeometryReader { proxy in
                ScrollView {
                    box
                        .frame(width: 560)
                        .padding(.top, 26)
                        // Before a folder is chosen there is no list, so the box sits in the middle of the window
                        // (the extra 52 offsets the bar above). With the list it starts at the top, as in the prototype.
                        .padding(.bottom, search == nil ? 26 + 52 : 26)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: search == nil ? .center : .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(Palette.window)
        #if DEBUG
        .task {
            // `-DotMDFirstLaunchSearch <path>` skips the open panel, for prototype checks.
            let arguments = ProcessInfo.processInfo.arguments
            guard search == nil, let index = arguments.firstIndex(of: "-DotMDFirstLaunchSearch"), index + 1 < arguments.count else { return }
            look(in: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
        }
        #endif
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The brand render the prototype shows. The running app's icon follows the system's icon style instead.
            Image("BrandIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 76, height: 76)
                .shadow(color: Color(red: 0, green: 42 / 255, blue: 26 / 255).opacity(0.28), radius: 12, y: 8)
                .padding(.leading, -6)
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                Icon("spark")
                Text(eyebrow)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Palette.accentInk)
            .padding(.bottom, 10)
            Text(heading)
                .font(.system(size: 32, weight: .bold, design: .serif))
                // AppKit tightens New York at display sizes and a browser doesn't; this restores the prototype's width.
                .tracking(0.13)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            explanation
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.ink3)
                .lineSpacing(4.8)
                .fixedSize(horizontal: false, vertical: true)
                // The prototype's 22 below, plus the half leading a browser puts above and below a 1.55 line.
                .padding(.top, 1)
                .padding(.bottom, 23.25)
            if let search, !search.candidates.isEmpty {
                FoundList(candidates: search.candidates, selected: $selected)
            }
            actions
                // The paragraph's 22 points already sit above the buttons when there is no list.
                .padding(.top, search?.candidates.isEmpty == false ? 18 : 0)
        }
    }

    private var eyebrow: String {
        guard let search else { return "Welcome to DotMD" }
        let count = search.suggestedCount
        if count == 1 { return "Found 1 folder where agents write" }
        if count > 1 { return "Found \(count) folders where agents write" }
        switch search.candidates.count {
        case 0: return "No agent folders found"
        case 1: return "Found 1 folder with lots of Markdown"
        default: return "Found \(search.candidates.count) folders with lots of Markdown"
        }
    }

    private var heading: String {
        guard let search else { return "Watch where your agents write" }
        return search.candidates.isEmpty ? "Nothing found in \(search.codeFolder.lastPathComponent)" : "Pick what DotMD should watch"
    }

    private var explanation: Text {
        guard let search else {
            return Text("Choose your code folder, like ~/code. DotMD finds the projects inside it by their CLAUDE.md, AGENTS.md and .cursor files. Nothing leaves your Mac.")
        }
        let folder = Text(RealHome.abbreviate(search.codeFolder)).bold()
        if search.candidates.isEmpty {
            return Text("In \(folder), DotMD found no CLAUDE.md, AGENTS.md or .cursor files, and no folder with lots of Markdown. Watch the whole folder, choose another, or open a single file.")
        }
        if search.suggestedCount == 0 {
            return Text("In \(folder), the folder you chose, DotMD found no CLAUDE.md, AGENTS.md or .cursor files, but these folders hold lots of Markdown. Nothing leaves your Mac.")
        }
        return Text("In \(folder), the folder you chose, DotMD found these agent folders by their CLAUDE.md, AGENTS.md and .cursor files. Nothing leaves your Mac.")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if search != nil {
                Button("Choose another folder…", action: chooseCodeFolder)
                    .buttonStyle(NoteButtonStyle())
            }
            Spacer(minLength: 0)
            Button("Open a file instead") { FileActions.openFilePanel() }
                .buttonStyle(FormButtonStyle())
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(FormButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(isSearching || isAdding || (search?.candidates.isEmpty == false && selected.isEmpty))
        }
    }

    private var primaryTitle: String {
        guard let search else { return isSearching ? "Looking for agent folders…" : "Choose code folder…" }
        if search.candidates.isEmpty { return "Watch \(search.codeFolder.lastPathComponent)" }
        return selected.count == 1 ? "Watch 1 folder" : "Watch \(selected.count) folders"
    }

    private func primaryAction() {
        guard let search else { return chooseCodeFolder() }
        if search.candidates.isEmpty {
            watch([search.codeFolder])
        } else {
            watch(search.candidates.filter { selected.contains($0.id) }.map(\.url))
        }
    }

    private func chooseCodeFolder() {
        guard let folder = FolderPicker.chooseFolder(message: "Choose the folder that holds your projects, like ~/code.", prompt: "Choose") else { return }
        look(in: folder)
    }

    private func look(in folder: URL) {
        isSearching = true
        Task {
            let candidates = await Task.detached(priority: .userInitiated) { AgentFolderFinder.candidates(in: folder) }.value
            isSearching = false
            selected = Set(candidates.filter(\.isSuggested).map(\.id))
            search = FolderSearch(codeFolder: folder, candidates: candidates)
        }
    }

    /// Watches each folder in turn. The Files window leaves first launch as soon as the first one is in the list.
    private func watch(_ urls: [URL]) {
        isAdding = true
        Task {
            var failure: Error?
            for url in urls {
                do {
                    try await library.addFolder(url)
                } catch {
                    failure = failure ?? error
                }
            }
            isAdding = false
            if let failure {
                let alert = NSAlert()
                alert.messageText = "DotMD couldn't watch every folder"
                alert.informativeText = failure.localizedDescription
                alert.runModal()
            }
        }
    }
}

/// The prototype's `.found`: a raised, rounded list of folders with a switch on each row.
private struct FoundList: View {
    let candidates: [AgentFolderCandidate]
    @Binding var selected: Set<String>
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                if index > 0 {
                    Palette.lineSoft.frame(height: 0.5)
                }
                Toggle(isOn: binding(for: candidate)) {
                    FoundRow(candidate: candidate, isOn: selected.contains(candidate.id))
                }
                .toggleStyle(FoundRowToggleStyle())
            }
        }
        .background(Palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .background {
            // The prototype's half point ring sits just outside the list's edge. A filled shape lands on whole
            // pixels where a half point stroke would blur across two.
            RoundedRectangle(cornerRadius: 14.5)
                .fill(Palette.line)
                .padding(-0.5)
        }
        .modifier(ShadowOne(shape: RoundedRectangle(cornerRadius: 14), fill: Palette.raised, dark: colorScheme == .dark))
    }

    private func binding(for candidate: AgentFolderCandidate) -> Binding<Bool> {
        Binding(
            get: { selected.contains(candidate.id) },
            set: { isOn in
                if isOn { selected.insert(candidate.id) } else { selected.remove(candidate.id) }
            }
        )
    }
}

/// The prototype's `.fr`: the folder path and what was found in it, then the Markdown count.
private struct FoundRow: View {
    let candidate: AgentFolderCandidate
    let isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(RealHome.abbreviate(candidate.url))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if candidate.markers.isEmpty {
                        Text("No agent files, lots of Markdown")
                    } else {
                        ForEach(candidate.markers, id: \.self) { marker in
                            Text(marker)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Palette.ink2)
                                // 15 points tall like the prototype's chip: SF Mono's line here is a point taller than a browser's.
                                .padding(.vertical, 0.5)
                                .padding(.horizontal, 6)
                                .background(Palette.fill, in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink3)
            }
            // Folders switched off fade back, as in the prototype; the count stays as it is.
            .opacity(isOn ? 1 : 0.55)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(candidate.markdownCount == 1 ? "1 Markdown file" : "\(candidate.markdownCount) Markdown files")
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink4)
                .fixedSize()
        }
    }
}

/// The whole row toggles. The switch overhangs its 20 point column into the gap, as the prototype's does.
private struct FoundRowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                SwitchMark(isOn: configuration.isOn)
                    .frame(width: 20, alignment: .leading)
                configuration.label
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// The prototype's `.sw`: a 28 by 16 point track with a 12 point knob.
private struct SwitchMark: View {
    let isOn: Bool

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
            }
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.14), value: isOn)
    }
}

/// The prototype's `.btn`: 30 points tall on a soft fill, or DotMD's green for the main action.
struct FormButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        FormButtonBody(label: configuration.label, primary: primary, pressed: configuration.isPressed)
    }
}

private struct FormButtonBody<Label: View>: View {
    let label: Label
    let primary: Bool
    let pressed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        label
            .font(.system(size: 13, weight: primary ? .semibold : .medium))
            .foregroundStyle(primary ? Palette.onAccent : Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(primary ? Palette.accent : hovering ? Palette.fill2 : Palette.fill, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? (pressed ? 0.8 : 1) : 0.45)
            .onHover { hovering = $0 }
    }
}

/// The prototype's `.note`: a quiet text action at the start of the button row.
private struct NoteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(configuration.isPressed ? Palette.ink3 : Palette.ink4)
            .contentShape(Rectangle())
    }
}
