import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", Base().show(), Sub().show())
    reload(1); print("after1 (want 10 20, the overridden private methods' new code):", Base().show(), Sub().show())
}}}
