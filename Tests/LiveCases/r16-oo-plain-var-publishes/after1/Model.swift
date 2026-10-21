import Foundation
import Combine
final class Model: ObservableObject {
    @Published var title = "a"
    var lastWidth = 0.0
}
func show(_ m: Model) -> String { "\(m.title) \(m.lastWidth)" }
func touch(_ m: Model) { m.lastWidth = 320 }
