import Foundation
struct Stack<T> { enum Mode { case a, b, c }; var mode = Mode.a; var items: [T] = [] }
func unbox(_ a: Any) -> String { if let m = a as? Stack<Int>.Mode { return "mode \(m)" }; return "not a mode" }
func show(_ s: Stack<Int>) -> String { "\(s.mode) \(Stack<Int>.Mode.c)" }
