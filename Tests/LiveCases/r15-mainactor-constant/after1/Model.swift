import Foundation
enum Config { @MainActor static let limit = 5 }
@MainActor func show() -> String { "limit=\(Config.limit)" }
