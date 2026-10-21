import Foundation
// The app's own protocol named Hashable, which brings no Equatable with it.
protocol Hashable {}
struct Tag: Hashable { var name: String }
func show(_ a: Any) -> String { "SHOWN \((a as? Tag)?.name ?? "?") equatable=\(a is any Equatable)" }
