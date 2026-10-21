import Foundation
enum Mood: CaseIterable { case happy, sad, angry, calm }
enum Catalog { static let count = Mood.allCases.count }
func show() -> String { "count=\(Catalog.count) live=\(Mood.allCases.count)" }
