import Foundation
class Base { var a = 1; var c = 3 }
class Sub: Base { var b = 2 }
func poke(_ s: Sub) { s.c = 30 }
func show(_ s: Sub) -> String { "a=\(s.a) b=\(s.b) c=\(s.c)" }
