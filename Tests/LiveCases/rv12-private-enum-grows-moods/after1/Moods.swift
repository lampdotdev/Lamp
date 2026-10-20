import Foundation
private enum Mood { case a, b, c }
func moods() -> String { [Mood.a, .b, .c].map { "\($0)" }.joined(separator: " ") }
