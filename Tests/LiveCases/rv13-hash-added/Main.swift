import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    for i in 0..<200 { Keys.add(Key(a: i, b: i * 7)) }
    print("before:", Keys.found(200) == 200 ? "all 200 found" : "some of the 200 lost")
    reload(1); print("after1 (the open set was laid out by the synthesized hash: want 200 found, or a reopen):", Keys.found(200) == 200 ? "all 200 found" : "some of the 200 lost")
}}}
