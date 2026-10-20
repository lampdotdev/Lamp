import Foundation
import Observation
struct Item: Codable, Identifiable, Hashable { var id = UUID(); var name: String }
@Observable final class Model {
    var items: [Item] = [] { didSet { save() } }
    var saved = 0
    var count: Int { items.count }
    var summary: String { "\(count) items: \(items.map(\.name).joined(separator: ","))" }
    func add(_ name: String) { items.append(Item(name: name)) }
    func save() { saved += 1 }
}
