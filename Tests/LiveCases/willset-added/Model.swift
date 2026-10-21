import Foundation
final class Game { var level = 1 }
func bump(_ g: Game) { g.level += 1 }
func show(_ g: Game) -> String { "level=\(g.level)" }
