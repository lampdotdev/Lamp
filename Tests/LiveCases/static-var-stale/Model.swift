import Foundation
enum Config { static var limit = 3; static let name = "a" }
var retries = 2
func show() -> String { "limit=\(Config.limit) name=\(Config.name) retries=\(retries)" }
