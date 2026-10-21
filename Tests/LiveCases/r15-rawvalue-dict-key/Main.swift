import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let budget = Budget(); budget.fill(); print("before:", budget.report())
    reload(1); print("after1 (want allFound=true, or a reopen: the dictionary was laid out by the old raw values):", budget.report())
    budget.fill(); print("after filling again (want count=1000):", budget.report())
}}}
