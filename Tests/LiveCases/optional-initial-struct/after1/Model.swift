import Foundation
struct Item: Equatable { var n = 1; var limit: Int? = 10 }
func show(_ i: Item) -> String { "\(i.n) \(i.limit.map(String.init) ?? "nil")" }
func same(_ a: Item, _ b: Item) -> Bool { a == b }
func setLimit(_ i: inout Item, _ n: Int?) { i.limit = n }
