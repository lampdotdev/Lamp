import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let h = Shop.Holder()
    print("before:", h.describe())
    reload(1); print("after1 (the field was the app's own Array and is Swift's now: want a reopen, or count=1):", h.describe())
}}}
