import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Model(); poke(m); print("before:", show(m))
    reload(1); poke(m); print("after (want log [1, 2] and b=7):", show(m))
}}}
