import Foundation
struct Pair { var a = 0; struct Sub { var b = 0; var c = 7 }; var sub = Sub() }
func show(_ p: Pair) -> String { "\(p.a) \(p.sub.b) \(p.sub.c)" }
