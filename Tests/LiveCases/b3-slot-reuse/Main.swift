import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let g = Game()
    print("before:", show(g))
    reload(1); bump(g); print("after1 (want score=42):", show(g))
    reload(2); print("after2 (no score):", show(g))
    reload(3); print("after3 (want score=0, fresh property):", show(g), "fresh object:", show(Game()))
}}}
