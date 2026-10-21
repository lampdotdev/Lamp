import Foundation
struct Box<T> { var v: T }
func show<T>(_ b: Box<T>) -> String { "\(b.v)" }
func made() -> Box<Int> { Box(v: 1) }
func bump<T>(_ b: inout Box<T>) {}
