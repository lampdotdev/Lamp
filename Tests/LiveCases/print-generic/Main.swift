import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let g = Game(); print("before:", show(g))
    reload(1); choose(g); print("after (want angry in all):", show(g))
}}}
