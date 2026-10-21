import SwiftUI
struct Look {
    struct Typeface { var design: Font.Design; var width: Font.Width; var weight: Font.Weight; var tracking: CGFloat }
    var wall: Color
    var display: Typeface
    static let taproom = Look(wall: Color(red: 0.58, green: 0.31, blue: 0.06), display: Typeface(design: .rounded, width: .condensed, weight: .heavy, tracking: 1))
    static let current = taproom
}
func show() -> String { "wall=\(Look.current.wall.description) design=\(Look.current.display.design) heavy=\(Look.current.display.weight == .heavy)" }
