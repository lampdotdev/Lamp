import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    let g = Game(); g.start(); print("--- before"); g.tick(); show(g)
    reload(1); choose(g); print("--- after (want angry/3/true everywhere, no crash)"); g.tick(); show(g)
}}}
