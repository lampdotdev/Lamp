import Foundation
private struct Row { var a = 1 }
final class HolderB { private var rows = [Row(a: 1), Row(a: 3)]; func sum() -> String { "\(rows.map { $0.a }.reduce(0, +))" } }
