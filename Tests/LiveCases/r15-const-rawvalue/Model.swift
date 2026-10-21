import Foundation
enum Kind: String { case a = "x", b = "z" }
enum Keys { static let first = Kind.a.rawValue }
func show() -> String { "constant=\(Keys.first) fresh=\(Kind.a.rawValue)" }
