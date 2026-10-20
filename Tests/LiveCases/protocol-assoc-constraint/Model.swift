import Foundation
protocol Container { associatedtype Item; var items: [Item] { get } }
struct Bag: Container { var items: [Int] }
final class Store { var bag = Bag(items: [1, 2, 2]) }
func report(_ s: Store) -> String { summary(s.bag) }
func summary<C: Container>(_ c: C) -> String { "count=\(c.items.count)" }
