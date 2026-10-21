import Foundation
@MainActor final class Model: Identifiable { var title = "a"; nonisolated let id = 42 }
@MainActor func show(_ m: Model) -> String { "\(m.title) id=\(m.id)" }
