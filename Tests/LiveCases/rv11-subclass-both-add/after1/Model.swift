import Foundation
class Base { var a = 1; var c = 3 }
class Sub: Base { var b = 2; var d = 4 }
func poke(_ s: Sub) { s.c = 30; s.d = 40 }
func show(_ s: Sub) -> String { "a=\(s.a) b=\(s.b) c=\(s.c) d=\(s.d)" }
