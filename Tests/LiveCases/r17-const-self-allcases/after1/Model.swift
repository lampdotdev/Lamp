import Foundation
enum Mood: CaseIterable {
    case calm, busy, away
    // Lists made once inside the enum, naming it as Self or not at all.
    static let all = Self.allCases
    static let count = allCases.count
}
extension Mood { static let names = allCases.map { "\($0)" } }
typealias Feeling = Mood
enum Picker { static let choices = Feeling.allCases }
func show() -> String { "all=\(Mood.all.count) count=\(Mood.count) names=\(Mood.names.count) alias=\(Picker.choices.count) live=\(Mood.allCases.count)" }
