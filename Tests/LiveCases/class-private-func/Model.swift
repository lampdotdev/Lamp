import Foundation
class Foo {
    class private func hidden() -> Int { 1 }
    class fileprivate var v: Int { 2 }
    static func s() -> Int { Foo.hidden() + Foo.v }
}
