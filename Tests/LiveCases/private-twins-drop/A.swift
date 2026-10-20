import Foundation
private struct Row { var a = 1; var b = 2 }
final class HolderA { private var rows = [Row(a: 1, b: 2), Row(a: 3, b: 4)]; func sum() -> Int { rows.map { $0.a }.reduce(0, +) } }
