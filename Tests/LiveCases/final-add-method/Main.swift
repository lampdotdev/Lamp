import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Sub(); let b: Base = s; print("before:", show(b))
    reload(1); print("after1 (want leaf method):", show(b))
    reload(2); print("after2:", show(b))
}}}
