import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let i = Item.made(); print("before:", show(i))
    reload(1); print("after1 (want \"a 1\" then \"a 6\"):", show(i), show(Item.made()))
}}}
