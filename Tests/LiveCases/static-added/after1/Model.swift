import Foundation
var globalCount = 0
final class Counter { static var count = 0; static func report() -> String { "\(count) \(globalCount)" }; static func bump() { count += 1; globalCount += 1 } }
