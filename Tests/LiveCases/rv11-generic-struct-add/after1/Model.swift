import Foundation
struct Box<T> { var v: T; var count = 0 }
func show<T>(_ b: Box<T>) -> String { "\(b.v) \(b.count)" }
func made() -> Box<Int> { Box(v: 1, count: 2) }
func bump<T>(_ b: inout Box<T>) { b.count = 3 }
