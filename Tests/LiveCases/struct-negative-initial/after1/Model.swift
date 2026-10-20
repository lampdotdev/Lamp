import Foundation
struct Item { var n = 1; var offset = -1 }
func show(_ i: Item) -> String { "\(i.n) \(i.offset)" }
func setOffset(_ i: inout Item, _ v: Int) { i.offset = v }
