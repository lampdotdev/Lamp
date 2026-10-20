import Foundation
struct Item { var a = 1; var total = 7 }
func show(_ i: Item) -> String { "\(i.total)" }
func poke(_ i: inout Item) { i.total = 9 }
