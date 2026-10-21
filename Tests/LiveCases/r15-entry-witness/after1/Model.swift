import Foundation
protocol Describable { func describe() -> String }
extension Describable { func describe() -> String { "default" } }
struct Item: Describable {}
extension Array: Describable where Element: Describable { func describe() -> String { "array" } }
func show(_ d: any Describable) -> String { d.describe() }
