import Foundation
struct Item: Equatable { var n = 1 }
func show(_ i: Item) -> String { "\(i.n)" }
func same(_ a: Item, _ b: Item) -> Bool { a == b }
func setLimit(_ i: inout Item, _ n: Int?) {}
