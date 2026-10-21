import Foundation
struct Item: Hashable { var n = 1; var limit: Int? = nil }
func clear(_ i: inout Item) { i.limit = nil }
func show(_ a: Item, _ b: Item) -> String { "\(a.limit.map(String.init) ?? "nil") \(b.limit.map(String.init) ?? "nil") equal=\(a == b) sameHash=\(a.hashValue == b.hashValue) set=\(Set([a, b]).count)" }
