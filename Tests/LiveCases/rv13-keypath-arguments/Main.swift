import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let saved = Paths.make(Int.self)
    print("before:", Paths.same(saved))
    reload(1); print("after1 (key paths made with arguments, again and again: want 50 of 50 equal to the one made before):", Paths.same(saved))
}}}
