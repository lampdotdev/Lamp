import Foundation
class Thing: NSObject { var a = 1; var b = "x"; func show() -> String { "a=\(a) b=\(b)" } }
final class Store { var thing = Thing() }
func show(_ s: Store) -> String { s.thing.show() }
func poke(_ s: Store) { s.thing.a += 1 }
