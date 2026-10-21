import Foundation
struct Chore { var title: String; var done: Bool; var priority = 0; init(title: String) { self.title = title; self.done = false; self.priority = 1 } }
final class Store { var chores = [Chore(title: "a")] }
func more(_ s: Store) { s.chores.append(Chore(title: "b")) }
func show(_ s: Store) -> String { s.chores.map { "\($0.title)/\($0.done)/\($0.priority)" }.joined(separator: " ") }
