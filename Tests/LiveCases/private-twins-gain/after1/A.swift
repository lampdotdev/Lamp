import Foundation
private struct Row { var a = 1; var b = 0 }
final class HolderA { private var rows = [Row(a: 1), Row(a: 3)]; func sum() -> Int { rows.map { $0.a + $0.b }.reduce(0, +) } }
