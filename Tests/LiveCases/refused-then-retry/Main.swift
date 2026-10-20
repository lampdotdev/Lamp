import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Store(); print("before:", show(s))
    reload(1); print("after1 (want reopen):", show(s))
    reload(2); print("after2 (want reopen):", show(s))
    reload(3); bump(s); print("after3 (want score=7):", show(s))
}}}
