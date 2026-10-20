import Foundation
enum A { struct Item { var x = 1 } }
enum B { struct Item { var y = 2 } }
func poke(_ a: inout A.Item, _ b: inout B.Item) {}
func show(_ a: A.Item, _ b: B.Item) -> String { "x=\(a.x) | y=\(b.y)" }
