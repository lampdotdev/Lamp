import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var a = Item(); let b = Item(); print("before:", show(a, b))
    reload(1); bump(&a); print("after1 (want equal=false):", show(a, b))
    reload(2); print("after2 (want equal=true, sameHash=true):", show(a, b), "fresh:", show(a, Item()))
}}}
