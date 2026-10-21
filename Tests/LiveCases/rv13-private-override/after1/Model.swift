import Foundation
class Base {
    fileprivate func secret() -> Int { 10 }
    func show() -> Int { secret() }
}
final class Sub: Base { override fileprivate func secret() -> Int { 20 } }
