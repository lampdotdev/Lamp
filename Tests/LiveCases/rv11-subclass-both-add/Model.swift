import Foundation
class Base { var a = 1 }
class Sub: Base { var b = 2 }
func poke(_ s: Sub) {}
func show(_ s: Sub) -> String { "a=\(s.a) b=\(s.b)" }
