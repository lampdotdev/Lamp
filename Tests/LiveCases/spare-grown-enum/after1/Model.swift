import SwiftUI
enum Mood { case happy, sad }
final class Game { var level = 1; var mood: Mood = .happy; var history: [Mood] = [] }
struct Settings { var volume = 1; var mood: Mood = .happy }
func choose(_ g: Game, _ s: inout Settings) { g.mood = .sad; g.history = [.sad, .sad]; s.mood = .sad }
func show(_ g: Game, _ s: Settings) -> String { "level=\(g.level) volume=\(s.volume) game.mood=\(g.mood) history=\(g.history) settings.mood=\(s.mood)" }
