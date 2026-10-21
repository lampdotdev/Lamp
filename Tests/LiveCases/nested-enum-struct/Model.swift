import Foundation
struct Game {
    enum Mood { case happy, sad }
    var mood: Mood = .happy
}
final class Holder { var g = Game() }
func choose(_ h: Holder) { h.g.mood = .sad }
func show(_ h: Holder) -> String { "mood=\(h.g.mood) mirror=\(Mirror(reflecting: h.g).children.map { "\($0.value)" })" }
