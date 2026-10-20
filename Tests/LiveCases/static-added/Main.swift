import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", Counter.report())
    reload(1); Counter.bump(); Counter.bump()
    print("after (want 2 2):", Counter.report())
}}}
