import Foundation
class Base { func name() -> String { "base" } }
final class Kid: Base { override func name() -> String { "kid" } }
func make() -> Any { 0 }
func describe(_ a: Any) -> String { (a as? Base).map { "\($0.name()):Base:\($0.name())" } ?? "not a Base" }
