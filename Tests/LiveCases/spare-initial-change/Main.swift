import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let i = Item(); print("before:", show(i))
    reload(1); print("after1 (want \"1 10\"):", show(i))
    reload(2); print("after2 (reopen expected; its reason should name the starting value):", show(i))
}}}
