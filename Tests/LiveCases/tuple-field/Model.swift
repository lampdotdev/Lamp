import Foundation
final class Game { var size: (w: Int, h: Int) = (3, 4) }
struct Pt { var p: (x: Double, y: Double) = (0, 0) }
func poke(_ g: Game, _ p: inout Pt) {}
func show(_ g: Game, _ p: Pt) -> String { "size=\(g.size) p=\(p.p)" }
