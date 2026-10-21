import Foundation
import Observation
struct Item { var name = "a"; var upper: String { name.uppercased() + "" } }
@Observable final class Model { var count = 0 }
enum Paths {
    static func made() -> [AnyKeyPath] { [\Item.name, \Item.upper, \Model.count, \Item.name.count] }
    static func compare(_ saved: [AnyKeyPath]) -> String {
        zip(saved, [\Item.name, \Item.upper, \Model.count, \Item.name.count] as [AnyKeyPath]).map { "\($0 == $1)" }.joined(separator: " ")
    }
}
