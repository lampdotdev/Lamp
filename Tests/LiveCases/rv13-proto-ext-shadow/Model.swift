import Foundation
protocol Labeled {}
extension Labeled { var label: String { "default" } }
struct Item: Labeled { var n = 1 }
final class Box: Labeled { var n = 1 }
