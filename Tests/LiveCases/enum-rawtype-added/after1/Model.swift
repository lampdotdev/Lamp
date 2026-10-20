import Foundation
enum Mood: String { case a, b, c }
func show(_ m: Mood) -> String { "\(m) \(m.rawValue) \(Mood(rawValue: "c").map { "\($0)" } ?? "none") \(Mood.c.rawValue)" }
