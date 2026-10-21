import Foundation
class Foo { func hi() -> String { "foo" } }
typealias Base = Foo
class Bar: Base { override func hi() -> String { "bar" } }
func describe() -> String { Foo().hi() + " " + Bar().hi() }
