// A private helper's local type with a stored some field, kept by an instance.
final class Card {
    let kept: any CustomStringConvertible
    init() { kept = Card.make() }
    private static func make() -> some CustomStringConvertible {
        struct Value: CustomStringConvertible {
            let value: some Equatable = 1
            var description: String { "value=\(value)" }
        }
        return Value()
    }
    func describe() -> String { kept.description }
}
