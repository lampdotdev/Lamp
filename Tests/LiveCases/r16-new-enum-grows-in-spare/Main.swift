import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var item = Item(); let box = Box(); print("before:", show(item, box))
    reload(1); choose(&item, box); print("after1 (want done done):", show(item, box))
    reload(2); print("after2 (want done done: what was chosen before the enum grew is kept):", show(item, box))
}}}
