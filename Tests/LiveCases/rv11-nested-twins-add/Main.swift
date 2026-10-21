import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var a = A.Item(), b = B.Item(); print("before:", show(a, b))
    reload(1); poke(&a, &b); print("after1 (want x=1 z=5 | y=2 z=\"q\"):", show(a, b))
}}}
