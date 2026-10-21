import Foundation
struct Item: Equatable, Hashable { var name: String; var done = false }
final class Store { var items = [Item(name: "a"), Item(name: "b")] }
func mark(_ s: Store) { s.items[0].done = true }
func show(_ s: Store) -> String { "equal=\(s.items[0] == Item(name: "a")) first=\(first(s)) set=\(Set(s.items + [Item(name: "a")]).count)" }
func first(_ s: Store) -> String { s.items[0].done ? "T" : "F" }
