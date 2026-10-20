import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", label())
    reload(1); print("after (want Taps: 1):", label())
    reload(2); print("after (want Taps: 1, doubled 2):", label())
}}}
