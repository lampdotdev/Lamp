final class Card {
    let kept: any CustomStringConvertible
    init() { kept = Card.make() }
    private static func make() -> some CustomStringConvertible {
        struct Value: CustomStringConvertible { var value: String; var description: String { "value=\(value)" } }
        return Value(value: "one")
    }
    func describe() -> String { kept.description }
}
