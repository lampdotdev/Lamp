import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Store(); print("before:", show(s))
    reload(1); print("after1 (want reopen; a reload reads B's fields where A2 lays them):", show(s))
}}}
