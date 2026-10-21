import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let a = HolderA(); let b = HolderB(); print("before:", a.sum(), b.sum())
    reload(1); print("after1 (want reopen; else A.sum should still be 4 and B.sum 10):", a.sum(), b.sum())
}}}
