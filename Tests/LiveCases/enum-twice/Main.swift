import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let g = Game(); print("before:", show(g))
    reload(1); choose(g); print("after1 (want angry everywhere, all=3):", show(g))
    reload(2); choose(g); print("after2 (want bored everywhere, all=4):", show(g))
}}}
