import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let d = Doc(named: "a"); print("before:", show(d))
    reload(1); print("after1 (want \"a 0\" then \"b 1\"):", show(d), show(Doc(named: "b")))
}}}
