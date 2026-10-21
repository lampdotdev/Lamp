func makeSalt() -> Int { 977 }
enum Config { static let salt = makeSalt() }
struct Key: Hashable {
    var a: Int
    func hash(into h: inout Hasher) { h.combine(a ^ Config.salt) }
}
enum Keys {
    static var all: Set<Key> = []
    static func add(_ k: Key) { all.insert(k) }
    static func found(_ n: Int) -> Int { (0..<n).filter { all.contains(Key(a: $0)) }.count }
}
