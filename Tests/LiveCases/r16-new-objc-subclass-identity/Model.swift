import Foundation
// A class hierarchy kept in one file, as SpriteKit nodes or AppKit views often are.
class Node: NSObject { var size = 1; @objc func name() -> String { "node" } }
final class Enemy: Node { override func name() -> String { "enemy" } }
func make() -> NSObject { Enemy() }
func describe(_ o: NSObject) -> String { "\((o as? Node)?.name() ?? "not a Node") kind=\(o.isKind(of: Node.self)) size=\((o as? Node)?.size ?? -1)" }
