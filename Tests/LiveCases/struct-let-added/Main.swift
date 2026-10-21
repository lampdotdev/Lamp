import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let i = Item(n: 2); print("before:", show(i))
    reload(1); print("after1 (want \"2 t\"):", show(i), show(Item(n: 3)))
    reload(2); print("after2 (Set<Int>() wanted in place):", show(i))
}}}
