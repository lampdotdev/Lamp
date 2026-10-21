import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", Settings.limit)
    reload(1); print("after1 (want 5 as a fresh launch, or a reopen as for a new starting value):", Settings.limit)
}}}
