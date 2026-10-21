import Foundation
struct Item { var n = 1; var greeting = "a\nb" }
func show(_ i: Item) -> String { "\(i.n) \(i.greeting.count)" }
