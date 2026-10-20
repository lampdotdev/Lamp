import Foundation
enum Config { static let size = 200 }
func show() -> String { "\(Config.size) \(type(of: Config.size)) half=\(Config.size / 2)" }
