import Foundation
enum Node { case leaf(Int); indirect case pair(Int, Int) }
final class Holder { var node: Node = .pair(3, 4); var label = "n" }
func show(_ h: Holder) -> String { switch h.node { case .leaf(let a): return "leaf \(a) \(h.label)"; case .pair(let a, let b): return "pair \(a) \(b) \(h.label)" } }
