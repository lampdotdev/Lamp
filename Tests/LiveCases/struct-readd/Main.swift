import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var s = Settings(); print("before:", show(s))
    reload(1); poke(&s); print("after1 (want bass=9):", show(s))
    reload(2); print("after2:", show(s))
    reload(3); print("after3 (want bass=5, fresh):", show(s), "fresh:", show(Settings()))
}}}
