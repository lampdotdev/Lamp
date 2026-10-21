import Foundation
enum Kind: String { case a = "y", b = "z" }
enum Keys { static let first = Kind.a.rawValue }
func show() -> String { "constant=\(Keys.first) fresh=\(Kind.a.rawValue)" }
