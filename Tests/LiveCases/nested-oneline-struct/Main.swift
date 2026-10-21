import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let p = Pair(); print("before:", show(p))
    reload(1); print("after1 (want \"0 0 7\"):", show(p))
}}}
