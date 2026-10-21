import Foundation
class Foo { func f() -> Int { 1 } }
class Bar: Foo { override func f() -> Int { 2 } }
func describe() -> String { "\(Foo().f()) \(Bar().f())" }
