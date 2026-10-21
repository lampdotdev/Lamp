import Foundation
struct Tag: Equatable, Hashable { var name: String }
func show(_ a: Any) -> String { "shown \((a as? Tag)?.name ?? "?") equatable=\(a is any Equatable)" }
