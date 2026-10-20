import Foundation
import Observation
struct Item: Codable, Identifiable, Hashable { var id = UUID(); var name: String }
@Observable final class Model {
    var items: [Item] = [] { didSet { save() } }
    var saved = 0
    var dirty = false { didSet { saved += 1000 } }
    var count: Int { items.count }
    var last: String { items.last?.name ?? "-" }
    var summary: String { "\(count) ITEMS: \(items.map(\.name).joined(separator: "+")) last=\(last) dirty=\(dirty)" }
    func add(_ name: String) { items.append(Item(name: name.uppercased())); dirty = true }
    func save() { saved += 10 }
}
