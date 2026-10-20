import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let a = HolderA(); let b = HolderB(); print("before:", a.sum(), b.sum())
    reload(1); print("after1 (want \"4 c=5\" and \"4 c=6\"):", a.sum(), b.sum())
}}}
