import Foundation
// The module is the app's name ("Case" here): an enum whose name begins with a word of it is mangled with a
// substitution for that word, as an app named Mood Tracker mangles its enum Mood.
enum CaseStatus: CaseIterable { case open, closed, archived }
func show() -> String { "cases=\(CaseStatus.allCases.count) last=\(CaseStatus.allCases.last!)" }
