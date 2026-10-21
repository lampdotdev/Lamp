import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    for _ in 0..<42 { Counter.bump() }
    print("before:", Counter.report())
    reload(1); Counter.bump(); print("after1 (want 43, the count the open app kept):", Counter.report())
}}}
