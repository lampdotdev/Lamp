import Foundation
struct Plain { var a = 1 }
func takes(_ p: UnsafeRawPointer, _ n: Int) -> Int { n }
func upload<T>(_ items: [T]) -> Int { takes(items, items.count) }
final class Holder { var items = [Plain()]; func show() -> String { "\(items[0].a) \(upload(items))" } }
