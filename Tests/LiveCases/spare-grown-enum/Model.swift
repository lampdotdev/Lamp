import SwiftUI
enum Mood { case happy, sad }
final class Game { var level = 1 }
struct Settings { var volume = 1 }
func choose(_ g: Game, _ s: inout Settings) {}
func show(_ g: Game, _ s: Settings) -> String { "level=\(g.level) volume=\(s.volume)" }
