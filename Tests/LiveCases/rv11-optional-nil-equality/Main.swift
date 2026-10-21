import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var a = Item(), b = Item(); print("before:", show(a, b))
    reload(1); clear(&a); print("after1 (want nil nil equal=true sameHash=true set=1):", show(a, b), "| both cleared:", { clear(&b); return show(a, b) }())
}}}
