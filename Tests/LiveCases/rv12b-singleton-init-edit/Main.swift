import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let first = ObjectIdentifier(Store.shared); Store.shared.count = 5
    print("before:", Store.shared.describe())
    reload(1); print("after1 (want the same store, count 5, in live):", Store.shared.describe(), ObjectIdentifier(Store.shared) == first ? "same" : "another")
}}}
