import Foundation
enum Store { static var total: Int = 3 }
enum Config { static let size = 200 }
func bump() { Store.total += 1 }
func show() -> String { "total=\(Store.total) size=\(Config.size)" }
