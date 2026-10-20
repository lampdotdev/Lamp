import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let v: Any = V.make(); print("before:", V.check(v))
    reload(1); print("after1 (formatting only; want true):", V.check(v))
    reload(2); print("after2 (moved; reopen expected):", V.check(v))
}}}
