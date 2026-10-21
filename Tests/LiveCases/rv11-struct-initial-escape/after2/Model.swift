import Foundation
struct Item { var n = 1; var greeting = "a\nb"; var mask = 0xFF }
func show(_ i: Item) -> String { "\(i.n) \(i.greeting.count) \(i.mask)" }
