import Foundation
final class Game { var level = 1; var score = 0 }
func bump(_ g: Game) { g.level += 1; g.score = 42 }
func show(_ g: Game) -> String { "level=\(g.level) score=\(g.score)" }
