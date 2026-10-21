import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let shelf = Shelf(); shelf.fill(); print("before:", shelf.report())
    reload(1); print("after1 (want has=true, or a reopen: the set was laid out by the old raw values):", shelf.report())
}}}
