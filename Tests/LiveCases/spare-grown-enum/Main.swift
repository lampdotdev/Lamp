import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    let g = Game(); var s = Settings()
    print("before:", show(g, s))
    reload(1); choose(g, &s)
    print("after1 (want mood=sad in all):", show(g, s))
    reload(2)
    print("after2 (want mood=sad still):", show(g, s))
}}}
