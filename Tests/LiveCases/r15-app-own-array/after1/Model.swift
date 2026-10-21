enum Shop {
    struct Array<T> { var value: T }
    final class Holder {
        var items: [Int] = [1]
        func describe() -> String { "count=\(items.count)" }
    }
}
