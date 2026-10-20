import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after (want 3 everywhere):", show())
}}}
