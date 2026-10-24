import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let box = Box(); print("before:", box.show())
    reload(1); print("after1 (want it live: a new callback starting as { n in … } runs its default):", box.show())
}}}
