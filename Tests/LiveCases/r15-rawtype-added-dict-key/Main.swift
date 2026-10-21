import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let budget = Budget(); budget.fill(); print("before:", budget.report())
    reload(1); print("after1 (want allFound=true, or a reopen: the dictionary was laid out by the hash the enum had without a raw type):", budget.report())
}}}
