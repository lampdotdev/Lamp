import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Model()
    print("before:", m.saved)
    reload(1); poke(m)
    print("after (want saved=1000 dirty=true):", m.saved, m.describe())
}}}
