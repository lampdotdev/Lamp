import Foundation
enum A { struct Item { var x = 1; var z = 0 } }
enum B { struct Item { var y = 2; var z = "" } }
func poke(_ a: inout A.Item, _ b: inout B.Item) { a.z = 5; b.z = "q" }
func show(_ a: A.Item, _ b: B.Item) -> String { "x=\(a.x) z=\(a.z) | y=\(b.y) z=\"\(b.z)\"" }
