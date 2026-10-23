import Foundation
struct Item { var title: String; var done = false }
// A model as agents write one, without `final`; nothing subclasses it.
@Observable class Store {
    var items = [Item(title: "Milk"), Item(title: "Eggs", done: true)]
    func clearDone() { items.removeAll(where: \.done) }
    func merge(from other: Store) { items += other.items }
    func openCount() -> Int { items.filter { !$0.done }.count }
    func summary() -> String { "\(openCount()) open of \(items.count)" }
}
