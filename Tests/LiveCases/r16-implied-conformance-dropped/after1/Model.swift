import Foundation
struct Tag: Hashable { var name: String }
func show(_ a: Any) -> String { "SHOWN \((a as? Tag)?.name ?? "?") equatable=\(a is any Equatable)" }
