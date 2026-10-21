import Foundation
struct Style: OptionSet { let rawValue: Int; static let bold = Style(rawValue: 1 << 0); static let italic = Style(rawValue: 1 << 1) }
final class Doc { var style: Style = [.bold, .italic]
    func describe() -> String { "bold=\(style.contains(.bold)) italic=\(style.contains(.italic))" } }
