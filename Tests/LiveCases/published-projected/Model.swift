import Foundation
import Combine
final class Search: ObservableObject { @Published var results: [String] = []; var bag = Set<AnyCancellable>()
    func show() -> String { "r=\(results.count)" } }
