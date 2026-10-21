import Foundation
enum Mood { case a, b, c }
struct Game { var volume = 1; var pick: Mood? = nil }
func show(_ g: Game) -> String { "volume=\(g.volume) pick=\(g.pick.map { "\($0)" } ?? "nil") isC=\(g.pick == .c)" }
func poke(_ g: inout Game) { g.pick = .c }
