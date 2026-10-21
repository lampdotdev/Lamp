import Foundation
enum Mood: CaseIterable {
    case calm, busy, away
    var label: String { "\(self)" }
}
enum Catalog {
    static let labels = Mood.allCases.map(\.label)
    static let shades: [Double] = {
        let base = 0.6
        return [base, base * 2]
    }()
}
final class Model { var count = 0; var added = [Mood]().map(\.label) }
func extra(_ model: Model) -> String { " added=\(model.added)" }
func show(_ model: Model) -> String {
    "labels=\(Catalog.labels.count) live=\(Mood.allCases.count) shades=\(Catalog.shades.map { String(format: "%.1f", $0) }.joined(separator: "/"))" + extra(model)
}
