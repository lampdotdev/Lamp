import Foundation
final class Settings { var name = "s"; var limit: Int? = 10 }
func show(_ s: Settings) -> String { "\(s.name) \(s.limit.map(String.init) ?? "nil")" }
func setLimit(_ s: Settings, _ n: Int?) { s.limit = n }
