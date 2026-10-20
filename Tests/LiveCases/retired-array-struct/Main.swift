import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Store(); print("before:", show(s))
    reload(1); mark(s); print("after1 (want equal=false first=T):", show(s))
    reload(2); print("after2 (want equal=true):", show(s))
    reload(3); print("after3 (want equal=true first=F, fresh place):", show(s))
    reload(4); print("after4 (want equal=true):", show(s))
    reload(5); print("after5 (want equal=true first=F, fresh place again):", show(s))
}}}
