import Foundation
private struct Row { var a = 1; var c = 5 }
final class HolderA { private var rows = [Row(a: 1), Row(a: 3)]; func sum() -> String { "\(rows.map { $0.a }.reduce(0, +)) c=\(rows[1].c)" } }
