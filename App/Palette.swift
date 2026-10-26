import DotMDCore
import SwiftUI

/// The prototype's sidebar colors, read by name from the asset catalog, which holds the light and dark values.
/// dotPen's green is read by name as well: Color.accentColor follows the person's system accent instead.
enum Palette {
    static let ink = Color("SideInk")
    static let ink3 = Color("SideInk3")
    static let ink4 = Color("SideInk4")
    static let line = Color("SideLine")
    static let fill = Color("SideFill")
    static let fill2 = Color("SideFill2")
    static let accent = Color("AccentColor")
    static let accentInk = Color("AccentInk")
    static let selection = Color("SelectionWash")
    /// The prototype's sidebar panel, a faint green-gray rather than the system's neutral sidebar.
    static let sidebar = Color("SideBackground")
    static let sidebarEdge = Color("SideEdge")
    static let window = Color("WindowBackground")
    static let ink2 = Color("SideInk2")
    /// The prototype's toolbar caps: white at 80% on the window (pre-blended), with a hairline edge.
    static let glass = Color("Glass")
    static let glassEdge = Color("GlassEdge")
    /// The document layout's bar, and the caps pre-blended over it.
    static let bar = Color("BarBackground")
    static let glassOnBar = Color("GlassOnBar")
    /// Raised surfaces, like the list of folders first launch found, with their softer row lines.
    static let raised = Color("RaisedBackground")
    static let lineSoft = Color("LineSoft")
    /// Text on dotPen's green.
    static let onAccent = Color("OnAccent")
    /// The comments panel: a selected comment's ring, and a resolved comment's quote bar.
    static let accentLine = Color("AccentLine")
    static let ink5 = Color("Ink5")
    /// The Send sheet's prompt, on the color code blocks use.
    static let codeBackground = Color("CodeBackground")
    /// Behind the Send sheet.
    static let scrim = Color("Scrim")
    /// The arrival banner's soft green.
    static let accentWash = Color("AccentWash")
    /// The palette and shortcuts overlay: a near-white panel over the window.
    static let pop = Color("Pop")
    /// Agent badges, as in the status line: Claude Code warm, Codex graphite. Never green.
    static let agentClaude = Color("AgentClaude")
    static let agentCodex = Color("AgentCodex")
    /// The prototype's amber, for a folder dotPen can't open.
    static let warn = Color("Warn")
}

/// One of the prototype's 16 point line icons, drawn at the given size and tinted by the foreground style.
struct Icon: View {
    let name: String
    var size: CGFloat = 16

    init(_ name: String, size: CGFloat = 16) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image("Icons/\(name)")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension DocumentKind {
    /// The prototype's icon for each kind of document.
    var iconName: String {
        switch self {
        case .readme: "book"
        case .plan: "plan"
        case .spec: "spec"
        case .changelog: "clock"
        case .agentInstructions: "gear"
        case .other: "doc"
        }
    }
}
