import Foundation
import Combine
final class Model: ObservableObject {
    @Published var title = "a"
}
func show(_ m: Model) -> String { m.title }
func touch(_ m: Model) {}
