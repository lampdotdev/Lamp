import Foundation
enum Mood { case a, b, c }
struct Game { var volume = 1 }
func show(_ g: Game) -> String { "volume=\(g.volume) cases=\(Mood.count)" }
func poke(_ g: inout Game) {}
extension Mood { static var count: Int { 3 } }
