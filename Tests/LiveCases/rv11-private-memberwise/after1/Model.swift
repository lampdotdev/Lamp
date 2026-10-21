import Foundation
struct Item { private let secret: Int; var name: String; var count = 0; func total() -> Int { secret + count } }
extension Item { static func made() -> Item { Item(secret: 1, name: "a", count: 5) } }
func show(_ i: Item) -> String { "\(i.name) \(i.total())" }
