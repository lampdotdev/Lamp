import Foundation
struct Settings { var volume = 1; var bass = 0 }
func poke(_ s: inout Settings) { s.volume += 1; s.bass = 9 }
func show(_ s: Settings) -> String { "volume=\(s.volume) bass=\(s.bass)" }
