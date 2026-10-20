import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let i = Item(); print("before:", show(i))
    reload(1); print("after1 (want \"1 0.001\"):", show(i))
}}}
