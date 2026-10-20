import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var g = Game(); print("before:", show(g))
    print("(control: after2 alone)")
    reload(1); print("after1 (want extra=0.0):", show(g))
}}}
