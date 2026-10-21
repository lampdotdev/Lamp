import Foundation
struct Item { private let secret: Int; var name: String; func total() -> Int { secret } }
extension Item { static func made() -> Item { Item(secret: 1, name: "a") } }
func show(_ i: Item) -> String { "\(i.name) \(i.total())" }
