import Foundation
final class Game { var level = 1; var score = 0 { willSet { print("will set score to", newValue) } } }
func bump(_ g: Game) { g.level += 1; g.score = 3 }
func show(_ g: Game) -> String { "level=\(g.level) score=\(g.score)" }
