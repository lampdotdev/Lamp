import Foundation
struct Settings { var volume = 1 }
func poke(_ s: inout Settings) { s.volume += 1 }
func show(_ s: Settings) -> String { "volume=\(s.volume)" }
