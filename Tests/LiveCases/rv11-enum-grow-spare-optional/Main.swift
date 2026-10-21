import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var g = Game(); print("before:", show(g))
    reload(1); poke(&g); print("after1 (want pick=c isC=true):", show(g))
    reload(2); poke(&g); print("after2 (want pick=d, in place or a reopen that names the spare):", show(g))
}}}
