import Foundation
// The app's own type by a system name, whose `.blue` is made again at every read.
struct Color: Equatable { var id = UUID(); static var blue: Color { Color() } }
struct Style { var title = "Card" }
func show(_ s: Style) -> String { "\(s.title)" }
