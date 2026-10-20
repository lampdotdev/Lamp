import Foundation
struct Item { var title: String; var action: () -> Void }
func show(_ b: Item) -> String { b.title }
func made() -> Item { Item(title: "y", action: {}) }
