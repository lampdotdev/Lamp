import Foundation
struct Item: CustomStringConvertible { var n = 1; var description: String { "item \(n)" } }
protocol Named { var name: String { get } }
struct Point { var x = 1 }
extension Point: Named { var name: String { "p\(x)" } }
func describe(_ a: Any) -> String { if let n = a as? Named { return "named \(n.name)" }; return "plain" }
func show() -> String { "\(Item()) \(describe(Point()))" }
