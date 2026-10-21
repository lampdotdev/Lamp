import Foundation
// An enum the session brought (it isn't in the app as it was built).
enum Filter: Hashable { case all, done, open }
func make() -> Any { Filter.done }
func check(_ a: Any) -> String { (a as? Filter).map { "\($0)" } ?? "not a Filter" }
