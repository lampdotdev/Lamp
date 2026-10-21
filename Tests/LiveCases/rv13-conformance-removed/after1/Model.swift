import Foundation
struct Item { var n = 1 }
protocol Named { var name: String { get } }
struct Point { var x = 1 }
func describe(_ a: Any) -> String { if let n = a as? Named { return "named \(n.name)" }; return "plain" }
func show() -> String { "\(Item()) \(describe(Point()))" }
