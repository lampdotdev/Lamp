import Foundation
class A1 { var p = 1 }
class A2 { var p = 1; var q = 2 }
class B: A1 { var r = 3; var label = "b"; func show() -> String { "p=\(p) r=\(r) label=\(label)" } }
final class Store { var b = B() }
func show(_ s: Store) -> String { s.b.show() }
func makeA2() -> A2 { A2() }
