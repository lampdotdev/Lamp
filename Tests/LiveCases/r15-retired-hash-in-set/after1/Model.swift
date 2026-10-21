import Foundation
struct Tag: Hashable { var n = 0; var badge = 0 }
final class Shelf {
    var picked = Set<Tag>()
    func pick() { for n in 0..<1000 { var t = Tag(n: n); t.badge = 9; picked.insert(t) } }
    func report() -> String { var t = Tag(n: 500); t.badge = 9; return "picked=\(picked.count) has=\(picked.contains(t))" }
}
