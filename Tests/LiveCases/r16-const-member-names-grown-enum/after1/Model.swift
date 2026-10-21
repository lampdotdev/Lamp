import Foundation
enum Mood: CaseIterable { case calm, busy, away }
// A constant made from a type whose default is made from the enum.
struct Picker { var choices = Mood.allCases }
enum Defaults { static let picker = Picker() }
func show() -> String { "constant=\(Defaults.picker.choices.count) fresh=\(Picker().choices.count)" }
