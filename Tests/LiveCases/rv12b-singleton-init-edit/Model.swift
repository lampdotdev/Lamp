final class Store {
    static let shared = Store()
    var count = 0
    init() { count = 1 }
    func describe() -> String { "count=\(count)" }
}
