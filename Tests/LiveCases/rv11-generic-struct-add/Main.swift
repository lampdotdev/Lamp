import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var b = Box(v: "s"); print("before:", show(b))
    reload(1); bump(&b); print("after1 (want \"s 3\" then \"1 2\"):", show(b), show(made()))
}}}
