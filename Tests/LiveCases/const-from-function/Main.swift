import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", table())
    reload(1); print("after1 (want [1, 2, 3], what build() makes now):", table(), "fresh:", build())
}}}
