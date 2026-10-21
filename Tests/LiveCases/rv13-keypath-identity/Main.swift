import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let saved = Paths.made()
    print("before:", Paths.compare(saved))
    reload(1); print("after1 (want true true true true, a key path to the same property is the same):", Paths.compare(saved))
}}}
