import Foundation
final class Helper { var name = "h" }
final class Owner { var helper: Helper? = nil; func show() -> String { helper?.name ?? "nil" } }
func show(_ o: Owner) -> String { o.show() }
func point(_ o: Owner, _ h: Helper) { o.helper = h }
