import Foundation
struct Color: Equatable { var id = UUID(); static var blue: Color { Color() } }
struct Style { var title = "Card"; var tint: Color = .blue }
func show(_ s: Style) -> String { "\(s.title) same=\(s.tint == s.tint)" }
