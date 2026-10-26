import DotMDCore
import SwiftUI

/// The Trail mark's line, in the prototype's 1000 point drawing: three bends to the right.
private func trailLine(in rect: CGRect, viewBox: CGRect) -> Path {
    let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + (x - viewBox.minX) * scale, y: rect.minY + (y - viewBox.minY) * scale)
    }
    var path = Path()
    path.move(to: point(232, 600))
    path.addCurve(to: point(446, 530), control1: point(290, 450), control2: point(382, 422))
    path.addCurve(to: point(660, 490), control1: point(510, 638), control2: point(596, 642))
    return path
}

/// The prototype's `.es-mark` on the empty state: the line draws itself in 1.1 s, then the dot pops in.
struct DrawnTrailMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    @State private var popped = false
    private static let viewBox = CGRect(x: 170, y: 330, width: 710, height: 400)

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let scale = min(rect.width / Self.viewBox.width, rect.height / Self.viewBox.height)
            ZStack(alignment: .topLeading) {
                trailLine(in: rect, viewBox: Self.viewBox)
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(style: StrokeStyle(lineWidth: 72 * scale, lineCap: .round))
                Circle()
                    .frame(width: 124 * scale, height: 124 * scale)
                    .position(x: (790 - Self.viewBox.minX) * scale, y: (430 - Self.viewBox.minY) * scale)
                    .scaleEffect(popped ? 1 : 0.001, anchor: UnitPoint(x: (790 - Self.viewBox.minX) / Self.viewBox.width,
                                                                     y: (430 - Self.viewBox.minY) / Self.viewBox.height))
            }
        }
        .frame(width: 120, height: 68)
        .foregroundStyle(Palette.ink5)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else {
                drawn = true
                popped = true
                return
            }
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.1).delay(0.15)) { drawn = true }
            withAnimation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.5).delay(1.15)) { popped = true }
        }
    }
}

/// The prototype's `.lostmark`: the Trail mark with a lock on its dot, shaking once when it appears.
struct LockedTrailMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shake: CGFloat = 0
    private static let viewBox = CGRect(x: 170, y: 300, width: 740, height: 430)

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let scale = min(size.width / Self.viewBox.width, size.height / Self.viewBox.height)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: (x - Self.viewBox.minX) * scale, y: (y - Self.viewBox.minY) * scale)
            }
            let ink = GraphicsContext.Shading.color(Palette.ink4)
            context.stroke(trailLine(in: rect, viewBox: Self.viewBox), with: ink, style: StrokeStyle(lineWidth: 72 * scale, lineCap: .round))
            let center = point(790, 430)
            let ring = Path(ellipseIn: CGRect(x: center.x - 86 * scale, y: center.y - 86 * scale, width: 172 * scale, height: 172 * scale))
            context.fill(ring, with: .color(Palette.window))
            context.stroke(ring, with: ink, lineWidth: 22 * scale)
            let body = Path(roundedRect: CGRect(origin: point(752, 428), size: CGSize(width: 76 * scale, height: 58 * scale)), cornerRadius: 12 * scale)
            context.fill(body, with: ink)
            var shackle = Path()
            shackle.move(to: point(766, 428))
            shackle.addLine(to: point(766, 410))
            shackle.addArc(center: point(790, 410), radius: 24 * scale, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            shackle.addLine(to: point(814, 428))
            context.stroke(shackle, with: ink, style: StrokeStyle(lineWidth: 16 * scale, lineCap: .round))
        }
        .frame(width: 124, height: 72)
        .offset(x: shake)
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(200))
            // The prototype's nudge: left 5, right 4, left 2, home, over half a second.
            for x: CGFloat in [-5, 4, -2, 0] {
                withAnimation(.easeOut(duration: 0.125)) { shake = x }
                try? await Task.sleep(for: .milliseconds(125))
            }
        }
    }
}

/// The prototype's `.es` block: a mark, a New York heading, a quiet paragraph, then actions or a hint.
private struct EdgeScreen<Mark: View, Footer: View>: View {
    let title: String
    let message: String
    @ViewBuilder let mark: Mark
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            mark.padding(.bottom, 18)
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink3)
                .lineSpacing(3.2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)
            footer
        }
        .frame(width: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.window)
    }
}

/// A watched folder dotPen can't open anymore. Comments and read history stay until the person stops watching it.
struct AccessLostView: View {
    let folder: FolderState
    @Environment(Library.self) private var library
    @State private var confirmingRemoval = false

    var body: some View {
        EdgeScreen(
            title: "\(folder.folder.name) is out of reach",
            message: "dotPen can no longer see this folder. Show it where \(folder.folder.name) lives now, and your comments and read history pick up right where you left them. Deleted it on purpose? Stop watching it."
        ) {
            LockedTrailMark()
        } footer: {
            HStack(spacing: 8) {
                Button("Locate Folder…", action: reconnect)
                    .buttonStyle(FormButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                Button("Stop Watching") { confirmingRemoval = true }
                    .buttonStyle(FormButtonStyle())
            }
        }
        .alert("Stop watching \(folder.folder.name)?", isPresented: $confirmingRemoval) {
            Button("Stop Watching", role: .destructive) { library.removeFolder(folder.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your files stay exactly where they are. dotPen forgets its comments and read history for this folder.")
        }
    }

    private func reconnect() {
        let path = URL(fileURLWithPath: folder.folder.path)
        guard let url = FolderPicker.chooseFolder(
            message: "Show dotPen where \(folder.folder.name) lives now.",
            prompt: "Reconnect",
            startingAt: path.deletingLastPathComponent()
        ) else { return }
        Task { try? await library.reconnect(folder.id, to: url) }
    }
}

/// Watched folders with no Markdown yet. The list stays empty until an agent writes a file.
struct EmptyFoldersView: View {
    let folders: [FolderState]

    var body: some View {
        EdgeScreen(title: title, message: "The moment an agent writes a .md file here, it lands in the list with a green dot.") {
            DrawnTrailMark()
        } footer: {
            hint
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink4)
        }
    }

    private var title: String {
        folders.count == 1 ? "No Markdown in \(folders[0].folder.name) yet" : "No Markdown in your folders yet"
    }

    @ViewBuilder private var hint: some View {
        if folders.count == 1 {
            HStack(spacing: 4) {
                Text("Watching")
                Text(RealHome.abbreviate(URL(fileURLWithPath: folders[0].folder.path)))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.fill, in: RoundedRectangle(cornerRadius: 5))
                Text("· 0 files")
            }
        } else {
            Text("Watching \(folders.count) folders · 0 files")
        }
    }
}
