import Foundation
struct Stage { var name = "stage" }
final class Box { var stage = Stage(); func show() -> String { stage.name } }
