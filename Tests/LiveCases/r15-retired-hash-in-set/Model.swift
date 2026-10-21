import Foundation
struct Tag: Hashable { var n = 0 }
final class Shelf {
    var picked = Set<Tag>()
    func pick() {}
    func report() -> String { "picked=\(picked.count) has=\(picked.contains(Tag(n: 500)))" }
}
