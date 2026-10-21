import Foundation
struct Item { var title: String; var n = 1 }
final class Counter { var step = 1 }
func local() -> Item { Item(title: "l") }
