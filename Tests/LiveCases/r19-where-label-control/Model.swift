import Foundation
struct Item { var title: String; var done = false }
// A model as agents write one, without `final`; nothing subclasses it.
@Observable class Store {
    var items = [Item(title: "Milk"), Item(title: "Eggs", done: true)]
    func clearDone() { items.removeAll { $0.done } }
    func merge(from other: Store) { items += other.items }
    func summary() -> String { "\(items.count) items" }
}
