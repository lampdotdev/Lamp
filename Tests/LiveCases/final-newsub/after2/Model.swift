import Foundation
class Foo { func f() -> Int { 1 } }
func describe() -> String { "\(Foo().f()) alone" }
