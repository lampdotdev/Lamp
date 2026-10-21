import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Settings(); print("before:", show(s))
    reload(1); print("after1 (want \"s 10\"):", show(s))
    setLimit(s, 3); print("after1 set (want \"s 3\"):", show(s))
}}}
