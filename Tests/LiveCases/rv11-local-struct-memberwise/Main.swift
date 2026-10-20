import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Shelf(); print("before:", s.pick())
    reload(1); print("after1 (want \"rice true\"):", s.pick())
}}}
