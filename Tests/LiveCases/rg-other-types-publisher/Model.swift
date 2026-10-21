import Foundation
import Combine
// Another type's $query, and the words "$query" in a string: neither is Search's publisher.
final class Filter: ObservableObject { @Published var query = ""; var bag = Set<AnyCancellable>()
    func watch() { $query.sink { _ in print("filter: use $query") }.store(in: &bag) } }
final class Search: ObservableObject { @Published var results: [String] = []
    func show() -> String { "r=\(results.count)" } }
