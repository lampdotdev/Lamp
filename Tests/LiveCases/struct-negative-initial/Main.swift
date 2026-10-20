import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var i = Item(); print("before:", show(i))
    reload(1); print("after1 (want \"1 -1\"):", show(i)); setOffset(&i, 3); print("after1 set (want \"1 3\"):", show(i))
}}}
