import Foundation
import Combine
final class Search: ObservableObject { @Published var results: [String] = []; @Published var query = ""; var bag = Set<AnyCancellable>()
    func watch() { $query.sink { [weak self] q in self?.results = [q] }.store(in: &bag) }
    func show() -> String { watch(); query = "x"; return "q=\(query) r=\(results)" } }
