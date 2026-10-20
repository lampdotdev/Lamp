import Foundation
struct Chore { var title: String; var done: Bool; init(title: String) { self.title = title; self.done = false } }
final class Store { var chores = [Chore(title: "a")] }
func more(_ s: Store) {}
func show(_ s: Store) -> String { s.chores.map { "\($0.title)/\($0.done)" }.joined(separator: " ") }
