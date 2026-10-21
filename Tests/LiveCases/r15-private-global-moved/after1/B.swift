import Foundation
func label() -> String { "b" }
private var count = 0
func bump() { count += 1 }
func report() -> Int { count }
