import Foundation
final class Game { var size: (w: Int, h: Int) = (3, 4); var score = 0; var box: (a: Int, b: Int) = (1, 2) }
struct Pt { var p: (x: Double, y: Double) = (0, 0); var tag = "t" }
func poke(_ g: Game, _ p: inout Pt) { g.score += 1; p.tag = "t2" }
func show(_ g: Game, _ p: Pt) -> String { "size=\(g.size) p=\(p.p) score=\(g.score) box=\(g.box) tag=\(p.tag)" }
