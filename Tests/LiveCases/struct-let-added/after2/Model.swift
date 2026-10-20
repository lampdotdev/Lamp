import Foundation
struct Item { var n = 1; let tag = "t"; var seen: Set<Int> = Set<Int>() }
func show(_ i: Item) -> String { "\(i.n) \(i.tag) \(i.seen.count)" }
