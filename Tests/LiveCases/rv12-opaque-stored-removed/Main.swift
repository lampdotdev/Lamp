import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let b = Box(); print("before:", b.describe())
    reload(1); print("after1 (an opaque stored field taken out of the open box: want a reopen):", b.describe())
}}}
