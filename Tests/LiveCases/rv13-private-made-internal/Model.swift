import Foundation
private struct Tag: Hashable { var n: Int }
final class Store {
    private var box: [Any] = [Tag(n: 1)]
    private var keys: Set<AnyHashable> = [AnyHashable(Tag(n: 1))]
    func show() -> String { "cast=\((box.first as? Tag)?.n ?? -1) key=\(keys.contains(AnyHashable(Tag(n: 1))))" }
}
