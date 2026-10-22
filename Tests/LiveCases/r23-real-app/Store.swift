import SwiftUI
import Observation
enum Category: CaseIterable { case food, home }
enum Theme { static let spacing: CGFloat = 8 }
struct Item: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var category: Category = .food
}
@Observable final class Store {
    var items: [Item] = [Item(name: "Milk"), Item(name: "Soap", category: .home)]
    func add(_ name: String) { items.append(Item(name: name)) }
}
