import Foundation
// The app's own protocol named Hashable, which brings no Equatable with it.
protocol Hashable {}
struct Tag: Hashable, Equatable { var name: String; static func == (a: Tag, b: Tag) -> Bool { a.name == b.name } }
func show(_ a: Any) -> String { "shown \((a as? Tag)?.name ?? "?") equatable=\(a is any Equatable)" }
