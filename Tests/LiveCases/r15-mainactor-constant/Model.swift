import Foundation
enum Config { @MainActor static let limit = 3 }
@MainActor func show() -> String { "limit=\(Config.limit)" }
