import Foundation
struct Item: Hashable { var volume = 1 }
func bump(_ s: inout Item) {}
func show(_ a: Item, _ b: Item) -> String { "equal=\(a == b) sameHash=\(a.hashValue == b.hashValue) set=\(Set([a, b]).count)" }
