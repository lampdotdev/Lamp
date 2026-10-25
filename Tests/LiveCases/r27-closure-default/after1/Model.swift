import Foundation
struct Stage { var name = "stage"; var onReview: (String, String) -> String = { a, b in "default \(a)\(b)" } }
final class Box { var stage = Stage(); func show() -> String { stage.name + " " + stage.onReview("x", "y") } }
