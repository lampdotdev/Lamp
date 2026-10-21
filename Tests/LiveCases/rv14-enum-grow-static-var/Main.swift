import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want 3 choices, or a reopen, as for any starting value that changed; and the same for both):", show(), showLater())
}}}
