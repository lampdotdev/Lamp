import Foundation
class Base { func name() -> String { "base" } }
final class Kid: Base { override func name() -> String { "kid" } }
func make() -> Base { Holder(value: 1) }
func show(_ b: Base) -> String { b.name() }
