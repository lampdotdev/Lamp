import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let h = Holder(); print("before:", show(h))
    reload(1); print("after1 (want pair 3 4; or a reopen):", show(h))
}}}
