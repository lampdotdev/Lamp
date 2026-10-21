import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    var i = Item(); print("before:", show(i))
    reload(1); print("after1 (want \"1 10\"):", show(i))
    print("after1 equal (want true):", same(i, Item()))
    setLimit(&i, nil); print("after1 set nil (want \"1 nil\"):", show(i))
}}}
