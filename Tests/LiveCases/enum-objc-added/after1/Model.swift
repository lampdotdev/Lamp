import Foundation
@objc enum Mood: Int { case happy, sad }
final class Store { var mood: Mood = .sad; var list: [Mood] = [.happy, .sad, .sad]; var pair: (Mood, Int) = (.sad, 7) }
func show(_ s: Store) -> String { "mood=\(s.mood) list=\(s.list) pair=\(s.pair)" }
