import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let shelf = Shelf(); print("before:", shelf.report())
    reload(1); shelf.pick(); print("after1 (want picked=1000 has=true):", shelf.report())
    reload(2); print("after2 (want picked=1000 has=true: the set the open app keeps still finds the tags it holds, or a reopen):", shelf.report())
}}}
