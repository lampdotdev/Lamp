struct Key: Hashable {
    var a: Int, b: Int
    func hash(into h: inout Hasher) { h.combine(a); h.combine(b) }
}
enum Keys {
    static var all: Set<Key> = []
    static func add(_ k: Key) { all.insert(k) }
    static func found(_ n: Int) -> Int { (0..<n).filter { all.contains(Key(a: $0, b: $0 * 7)) }.count }
}
