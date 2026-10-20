import Foundation
private enum Mood { case a, b }
func moods() -> String { [Mood.a, .b].map { "\($0)" }.joined(separator: " ") }
