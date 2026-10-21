import Foundation
struct Style: OptionSet { let rawValue: Int; static let underline = Style(rawValue: 1 << 0); static let bold = Style(rawValue: 1 << 1); static let italic = Style(rawValue: 1 << 2) }
final class Doc { var style: Style = [.bold, .italic]
    func describe() -> String { "bold=\(style.contains(.bold)) italic=\(style.contains(.italic)) underline=\(style.contains(.underline))" } }
