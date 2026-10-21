import Foundation
enum Kind: String { case a = "z", b = "y" }
struct Tag: Hashable {
    var n: Int; var kind: Kind
    func hash(into hasher: inout Hasher) { hasher.combine(n); hasher.combine(kind.rawValue) }
    static func == (l: Tag, r: Tag) -> Bool { l.n == r.n && l.kind == r.kind }
}
final class Shelf {
    var picked = Set<Tag>()
    func fill() { picked = Set((0..<1000).map { Tag(n: $0, kind: .a) }) }
    func report() -> String { "has=\(picked.contains(Tag(n: 500, kind: .a))) count=\(picked.union((0..<1000).map { Tag(n: $0, kind: .a) }).count)" }
}
