import Foundation
struct Item { var title: String; var n = 2 }
final class Counter { var step = 2 }
func local() -> Item { Item(title: "l") }
