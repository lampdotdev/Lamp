import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Search(); print("before:", m.show())
    reload(1); print("after1 (want q=x in place: the $query used is Filter's, not Search's):", m.show())
}}}
