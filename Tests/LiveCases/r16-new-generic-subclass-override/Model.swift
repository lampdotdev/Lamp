import Foundation
class Base { func name() -> String { "base" } }
final class Kid: Base { override func name() -> String { "kid" } }
func make() -> Base { Base() }
func show(_ b: Base) -> String { b.name() }
