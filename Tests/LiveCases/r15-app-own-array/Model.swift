// A type of the app's own named as Swift's is, inside another.
enum Shop {
    struct Array<T> { var value: T }
    final class Holder {
        var items: Array<Int> = Array(value: 7)
        func describe() -> String { "value=\(items.value)" }
    }
}
