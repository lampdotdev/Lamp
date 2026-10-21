import Foundation
enum Mood: CaseIterable { case happy, sad }
// Lists made once from the enum, as an agent writes a picker's choices.
enum Catalog { static let moods = Mood.allCases; static let names = Mood.allCases.map { "\($0)" } }
let allMoods: [Mood] = Mood.allCases
func show() -> String { "static=\(Catalog.moods.count) names=\(Catalog.names.count) global=\(allMoods.count) live=\(Mood.allCases.count)" }
