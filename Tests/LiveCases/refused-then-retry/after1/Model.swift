import Foundation
enum Mood { case happy, sad, angry }
struct Game: Equatable { var volume = 1; var mood: Mood? = nil; var score = 0 }
final class Store { var game = Game() }
func bump(_ s: Store) { s.game.score = 7; s.game.mood = .angry }
func show(_ s: Store) -> String { "volume=\(s.game.volume) score=\(score(s))" }
func score(_ s: Store) -> Int { s.game.score }
