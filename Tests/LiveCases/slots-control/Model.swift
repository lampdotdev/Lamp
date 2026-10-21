import Foundation
enum Mood { case happy, sad }
struct Game { var volume = 1; var mood: Mood? = nil }
func show(_ g: Game) -> String { "volume=\(g.volume)" }
