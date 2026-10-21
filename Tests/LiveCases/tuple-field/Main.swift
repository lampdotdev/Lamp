import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let g = Game(); var p = Pt(); print("before:", show(g, p))
    reload(1); poke(g, &p); print("after1 (want score=1 box=(a: 1, b: 2) tag=t2):", show(g, p))
}}}
