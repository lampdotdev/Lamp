import Foundation
enum Mood { case happy, sad, angry }
struct Game { var volume = 1; var mood: Mood? = nil; var extra: Int = 0 }
func show(_ g: Game) -> String { "volume=\(g.volume) extra=\(g.extra)" }
