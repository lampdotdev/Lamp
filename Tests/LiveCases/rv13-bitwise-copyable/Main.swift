import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let g = Game(); print("before:", g.show())
    reload(1); print("after1 (want \"level=1 lives=3\", the new property in its spare):", g.show())
}}}
