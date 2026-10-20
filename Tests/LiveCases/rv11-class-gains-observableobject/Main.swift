import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Model(); print("before:", m.describe())
    reload(1); print("after1 (want v1 in place: a protocol was added, no superclass):", m.describe())
}}}
