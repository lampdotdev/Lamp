import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Model(); print("before:", m.show())
    reload(1); print("after1 (reopen expected, with a reason naming lazy):", m.show())
}}}
