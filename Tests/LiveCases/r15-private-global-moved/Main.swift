import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    for _ in 0..<42 { bump() }
    print("before:", report())
    reload(1); bump(); print("after1 (want 43, the count the open app kept, or a reopen):", report())
}}}
