import Foundation
enum Mood { case a, b }
struct Game { var volume = 1; var pick: Mood? = nil }
func show(_ g: Game) -> String { "volume=\(g.volume) cases=\(Mood.count) pick=\(g.pick.map { "\($0)" } ?? "nil")" }
func poke(_ g: inout Game) { g.pick = .b }
extension Mood { static var count: Int { 2 } }
