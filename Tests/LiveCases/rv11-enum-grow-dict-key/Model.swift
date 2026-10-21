import Foundation
enum Mood: Hashable { case a, b }
enum Tally { static var counts: [Mood: Int] = [.a: 1] }
func bump() { Tally.counts[.b, default: 0] += 1 }
func show() -> String { Tally.counts.sorted { "\($0.key)" < "\($1.key)" }.map { "\($0.key):\($0.value)" }.joined(separator: " ") + " a=\(Tally.counts[.a] ?? -1) b=\(Tally.counts[.b] ?? -1)" }
