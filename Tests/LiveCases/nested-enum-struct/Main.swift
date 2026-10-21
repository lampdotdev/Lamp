import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let h = Holder(); print("before:", show(h))
    reload(1); choose(h); print("after (want angry, no crash):", show(h))
}}}
