import Foundation
enum Settings {
    enum Mood { case happy, sad, angry }
}
struct Game { var mood: Settings.Mood = .happy }
final class Holder { var g = Game() }
func choose(_ h: Holder) { h.g.mood = .angry }
func show(_ h: Holder) -> String { "mood=\(h.g.mood) mirror=\(Mirror(reflecting: h.g).children.map { "\($0.value)" })" }
