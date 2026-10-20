import Foundation
enum Mood { case a, b }
struct Item { var n = 1 }
func show(_ i: Item) -> String { "\(i.n)" }
func pick(_ i: inout Item) {}
