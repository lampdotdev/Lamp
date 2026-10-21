import Foundation
final class Holder<T>: Base { let value: T; init(value: T) { self.value = value }; override func name() -> String { "holder" } }
