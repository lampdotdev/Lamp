import Foundation
struct Item { var title: String; var action: () -> Void; var badge = 0 }
func show(_ b: Item) -> String { "\(b.title) \(b.badge)" }
func made() -> Item { Item(title: "y", action: {}, badge: 2) }
