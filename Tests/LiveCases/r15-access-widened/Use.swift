import Foundation
// Unchanged: which price() this calls depends on whether Shop's own is visible from this file.
extension Shop { func total() -> Int { price() } }
func show() -> String { "total=\(Shop().total())" }
