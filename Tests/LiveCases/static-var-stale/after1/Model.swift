import Foundation
enum Config { static var limit = 5; static let name = "b" }
var retries = 4
func show() -> String { "limit=\(Config.limit) name=\(Config.name) retries=\(retries)" }
