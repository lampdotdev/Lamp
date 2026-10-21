// A private helper returning a type declared inside it, kept by an instance.
final class Card {
    let kept: any CustomStringConvertible
    init() { kept = Card.make() }
    private static func make() -> some CustomStringConvertible {
        struct Value: CustomStringConvertible { var value: Int; var description: String { "value=\(value)" } }
        return Value(value: 1)
    }
    func describe() -> String { kept.description }
}
