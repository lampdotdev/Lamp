import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let g = Game(); g.start(); g.tick(); print("before:", show(g))
    reload(1); choose(g); g.tick(); print("after (want angry in all):", show(g))
}}}
