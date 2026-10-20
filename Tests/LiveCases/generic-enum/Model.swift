import Foundation
enum Box<T> { case a, b }
final class Game { var box: Box<Int> = .a; var list: [Box<String>] = [.a] }
func choose(_ g: Game) { g.box = .b; g.list = [.b] }
func show(_ g: Game) -> String { "box=\(g.box) list=\(g.list) mirror=\(Mirror(reflecting: g).children.map { "\($0.value)" })" }
