import Foundation
class Base {
    fileprivate func secret() -> Int { 1 }
    func show() -> Int { secret() }
}
final class Sub: Base { override fileprivate func secret() -> Int { 2 } }
