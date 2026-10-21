import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var i = Item(); print("before:", show(i))
    reload(1); print("after1 (want 7 then 9):", show(i), { poke(&i); return show(i) }())
}}}
