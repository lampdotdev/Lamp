import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", eps())
    reload(1); print("after1 (want 1e-07):", eps())
}}}
