import SwiftUI
// A theme kept as constants of its own type, chosen by another constant.
struct Look {
    static let current = Look.taproom
    var accent: Int
    var wall: Color = .red
    var scheme: ColorScheme = .dark
    var glow: (red: Double, green: Double) = (1, 1)
}
extension Look {
    static let taproom = Look(accent: 2)
}
func show() -> String { "accent=\(Look.current.accent)" }
