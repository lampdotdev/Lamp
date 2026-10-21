import Foundation
struct Item: Hashable { var volume = 1; var bass = 5 }
func bump(_ s: inout Item) { s.bass = 9 }
func show(_ a: Item, _ b: Item) -> String { "equal=\(a == b) sameHash=\(a.hashValue == b.hashValue) set=\(Set([a, b]).count)" }
