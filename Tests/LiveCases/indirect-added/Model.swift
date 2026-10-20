import Foundation
enum Tree { case leaf(Int), node(Int, Int) }
final class Store { var tree: Tree = .node(1, 2); var list: [Tree] = [.leaf(3), .node(4, 5)] }
func show(_ s: Store) -> String { "\(describe(s.tree)) \(s.list.map(describe))" }
func describe(_ t: Tree) -> String { switch t { case .leaf(let v): "leaf \(v)"; case .node(let a, let b): "node \(a),\(b)" } }
