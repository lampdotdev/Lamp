import Foundation
@MainActor final class Model { var title = "a" }
@MainActor func show(_ m: Model) -> String { m.title }
