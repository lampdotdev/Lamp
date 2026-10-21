import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    let g = Game(); g.start(); g.tick(); print("before:", show(g))
    reload(1); choose(g); g.tick(); print("after (want sad=1 angry=1 last=angry):", show(g))
}}}
