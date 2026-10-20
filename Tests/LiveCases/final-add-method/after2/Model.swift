import Foundation
class Base { func f() -> Int { 1 }; func g() -> Int { 10 } }
class Sub: Base { override func f() -> Int { 2 }; func leaf() -> Int { 20 } }
func show(_ b: Base) -> String { "f=\(b.f()) g=\(b.g()) leaf=\((b as? Sub)?.leaf() ?? -1)" }
