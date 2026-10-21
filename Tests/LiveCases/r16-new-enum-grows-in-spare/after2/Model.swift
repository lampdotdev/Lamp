import Foundation
// The session brings an enum and keeps one in a struct and in a class.
enum Filter { case all, done, open }
struct Item { var title = "x"; var filter: Filter = .all }
final class Box { var count = 0; var filter: Filter = .all }
func choose(_ i: inout Item, _ b: Box) { i.filter = .done; b.filter = .done }
func show(_ i: Item, _ b: Box) -> String { "\(i.filter) \(b.filter)" }
