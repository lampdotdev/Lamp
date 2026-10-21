import Foundation
final class Game { var level = 1; var score = "none" }
func bump(_ g: Game) { g.level += 1; g.score = "seven" }
func show(_ g: Game) -> String { "level=\(g.level) score=\(g.score)" }
