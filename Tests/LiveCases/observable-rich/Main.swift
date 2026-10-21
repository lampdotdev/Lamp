import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Model(); m.add("a")
    print("before:", m.summary, m.saved)
    reload(1); m.add("b"); print("after1:", m.summary, m.saved)
    reload(2); m.add("c"); print("after2:", m.summary, m.saved)
    reload(3); m.add("d"); print("after3:", m.summary, m.saved)
}}}
