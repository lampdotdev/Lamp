import Foundation
struct Item { var a = 1; var total: Int { a * 2 } }
func show(_ i: Item) -> String { "\(i.total)" }
func poke(_ i: inout Item) {}
