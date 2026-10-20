import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Model(); print("before:", probe(m))
    reload(1); print("after1 (want \"ignored: fired=false\"):", probe(m))
}}}
