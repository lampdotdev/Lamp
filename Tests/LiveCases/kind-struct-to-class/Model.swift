import Foundation
struct Item { var name: String; var count: Int }
final class Store {
    var items: [Item] = [Item(name: "a", count: 1), Item(name: "b", count: 2)]
    var one = Item(name: "c", count: 3)
}
func bump(_ s: Store) { s.one.count += 1 }
func show(_ s: Store) -> String { "one=\(s.one.name)/\(s.one.count) items=\(s.items.map { "\($0.name)/\($0.count)" })" }
