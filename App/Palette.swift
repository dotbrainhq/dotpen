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
}
