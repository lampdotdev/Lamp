import Foundation
enum Store { static var count = 0; static var total = 0.0; static var tag = "t"; static var flag = false; static var items: [Int] = [] }
nonisolated(unsafe) var globalCount = 0
final class Box { static var name = "n" }
func bump() { Store.count += 1; Store.total += 1; Store.tag = "t1"; Store.flag = true; Store.items.append(1); globalCount += 1; Box.name = "n1" }
func report() -> String { "count=\(Store.count) total=\(Store.total) tag=\(Store.tag) flag=\(Store.flag) items=\(Store.items.count) global=\(globalCount) name=\(Box.name)" }
func oldRead() -> String { report() }
