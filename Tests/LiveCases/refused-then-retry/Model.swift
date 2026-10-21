import Foundation
enum Mood { case happy, sad }
struct Game: Equatable { var volume = 1; var mood: Mood? = nil }
final class Store { var game = Game() }
func bump(_ s: Store) {}
func show(_ s: Store) -> String { "volume=\(s.game.volume) score=\(score(s))" }
func score(_ s: Store) -> Int { -1 }
