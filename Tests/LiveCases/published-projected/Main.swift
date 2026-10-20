import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Search(); print("before:", m.show())
    reload(1); print("after1 (want in place, \"q=\" then watched):", m.show())
}}}
