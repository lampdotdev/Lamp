import Foundation
struct Item { var n = 1 }
func show(_ i: Item) -> String { "\(i.n)" }
func setOffset(_ i: inout Item, _ v: Int) {}
