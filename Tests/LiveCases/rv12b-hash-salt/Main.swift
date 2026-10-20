import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    for i in 0..<200 { Keys.add(Key(a: i)) }
    print("before:", Keys.found(200), "of 200 found")
    reload(1); print("after1 (the hash's salt changed, its text didn't: want 200 found, or a reopen):", Keys.found(200), "of 200 found")
}}}
