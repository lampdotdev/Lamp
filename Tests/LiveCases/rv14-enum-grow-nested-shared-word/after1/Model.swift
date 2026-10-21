import Foundation
struct MoodBoard { enum Mood: CaseIterable { case calm, busy, away } }
func show() -> String { "cases=\(MoodBoard.Mood.allCases.count)" }
