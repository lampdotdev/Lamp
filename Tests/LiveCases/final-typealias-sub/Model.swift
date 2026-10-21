import Foundation
class Foo { func hi() -> String { "foo" } }
typealias Base = Foo
func describe() -> String { Foo().hi() }
