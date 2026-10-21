import Foundation
enum Mood { case a, b, c }
struct Item { var n = 1; var mood: Mood? = nil }
func show(_ i: Item) -> String { "\(i.n) \(i.mood.map { "\($0)" } ?? "none")" }
func pick(_ i: inout Item) { i.mood = .c }
