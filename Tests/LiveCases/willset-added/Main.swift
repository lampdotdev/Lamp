import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let g = Game(); print("before:", show(g))
    reload(1); bump(g); print("after:", show(g))
}}}
