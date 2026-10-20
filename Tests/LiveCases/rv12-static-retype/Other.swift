import Foundation
func otherBump() { Store.total += 1 }
func otherShow() -> String { "total=\(Store.total) size=\(Config.size)" }
