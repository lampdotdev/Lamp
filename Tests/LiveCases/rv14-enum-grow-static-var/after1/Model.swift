import Foundation
enum Mood: CaseIterable { case calm, busy, away }
// Two stored statics made from the enum: the first read before the change, the second only after it.
enum Catalog { static var choices: [Mood] = Mood.allCases; static var later: [Mood] = Mood.allCases }
func show() -> String { "choices=\(Catalog.choices.count)" }
func showLater() -> String { "later=\(Catalog.later.count)" }
