struct Item: Equatable { var n = 1; var badge = 0 }
struct Pair<T> where T: Equatable { var a: T; var b: Item }
enum Shop {
    static var item = Item()
    static func describe() -> String { item.badge = 3; return "\(item) \(Pair(a: 5, b: item))" }
}
