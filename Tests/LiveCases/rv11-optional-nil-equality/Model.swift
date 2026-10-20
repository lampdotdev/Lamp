import Foundation
struct Item: Hashable { var n = 1 }
func clear(_ i: inout Item) {}
func show(_ a: Item, _ b: Item) -> String { "equal=\(a == b) sameHash=\(a.hashValue == b.hashValue) set=\(Set([a, b]).count)" }
