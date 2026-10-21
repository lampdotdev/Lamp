import Foundation
struct Item { var title = "x" }
final class Box { var count = 0 }
func choose(_ i: inout Item, _ b: Box) {}
func show(_ i: Item, _ b: Box) -> String { i.title }
