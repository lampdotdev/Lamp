import Foundation
// A model marked @MainActor, as agents often write them, with a constant read from code that isn't.
@MainActor final class Store {
    static let pageSize = 20
    var items: [Int] = []
}
