import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", area())
    reload(1); print("after1 (want 400, the constant's new value read where it was read before):", area())
}}}
