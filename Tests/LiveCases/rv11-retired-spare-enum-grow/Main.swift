import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var g = Game(); print("before:", show(g))
    reload(1); poke(&g); print("after1:", show(g))
    reload(2); print("after2:", show(g))
    reload(3); print("after3 (want in place: nothing reads the retired place):", show(g))
}}}
