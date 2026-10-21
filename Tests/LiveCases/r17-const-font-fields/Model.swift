import SwiftUI
struct Look {
    struct Typeface { var design: Font.Design; var width: Font.Width; var weight: Font.Weight; var tracking: CGFloat }
    var wall: Color
    var display: Typeface
    static let taproom = Look(wall: Color(red: 0.20, green: 0.40, blue: 0.06), display: Typeface(design: .rounded, width: .condensed, weight: .heavy, tracking: 1))
    static let current = Look(wall: Color(red: 0.5, green: 0.1, blue: 0.1), display: Typeface(design: .serif, width: .standard, weight: .regular, tracking: 0))
}
func show() -> String { "wall=\(Look.current.wall.description) design=\(Look.current.display.design) heavy=\(Look.current.display.weight == .heavy)" }
