import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let h = Holder(); print("before:", report(h))
    reload(1)
    print("after (want 3 cases, angry decoded):", report(h))
}}}
