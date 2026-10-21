import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Model(); let p = Plain()
    print("before:", m.saved, p.saved)
    reload(1); poke(m, p)
    print("after (want 1000 1000 if the didSet ran):", m.saved, p.saved)
}}}
