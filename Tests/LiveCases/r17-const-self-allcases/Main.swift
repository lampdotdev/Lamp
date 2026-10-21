import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want 3 everywhere, like live, or a reopen):", show())
}}}
