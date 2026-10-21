import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var g = Game(); print("before:", show(g))
    reload(1); print("after1 (reopen expected: Mood? held):", show(g))
    reload(2); print("after2 (want extra=0.0):", show(g))
}}}
