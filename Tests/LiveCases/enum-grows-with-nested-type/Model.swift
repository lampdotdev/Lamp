import Foundation
enum Mood { case a, b; struct Info: Equatable { var n = 1 } }
func make() -> Any { Mood.Info(n: 2) }
func read(_ x: Any) -> String { (x as? Mood.Info).map { "\($0.n)" } ?? "not info" }
