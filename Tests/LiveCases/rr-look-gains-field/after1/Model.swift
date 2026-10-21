import SwiftUI
// A theme kept as constants of its own type, chosen by another constant.
struct Look {
    static let current = Look.taproom
    var accent: Int
    var wall: Color = .red
    var scheme: ColorScheme = .dark
    var glow: (red: Double, green: Double) = (1, 1)
    var softShade = false
}
extension Look {
    static let taproom = Look(accent: 2, softShade: true)
}
func show() -> String { "accent=\(Look.current.accent) soft=\(Look.current.softShade)" }
