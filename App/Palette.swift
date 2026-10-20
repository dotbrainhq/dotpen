import DotMDCore
import SwiftUI

/// The prototype's sidebar colors, read by name from the asset catalog, which holds the light and dark values.
/// DotMD's green is read by name as well: Color.accentColor follows the person's system accent instead.
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
