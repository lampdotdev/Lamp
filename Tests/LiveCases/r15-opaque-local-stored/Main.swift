import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let c = Card()
    print("before:", c.describe())
    reload(1); print("after1 (the kept value's local type keeps a some Equatable that is a String now: want a reopen, or value=one):", c.describe())
}}}
