import Foundation
enum Mood { case a, b }
struct Game { var volume = 1 }
func show(_ g: Game) -> String { "volume=\(g.volume)" }
func poke(_ g: inout Game) {}
