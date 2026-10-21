import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", check(make()))
    reload(1)
    let kept = make()
    print("after1 (want done):", check(kept))
    reload(2)
    print("after2 (want done: a value made before the enum grew is still a Filter):", check(kept), "fresh:", check(make()))
}}}
