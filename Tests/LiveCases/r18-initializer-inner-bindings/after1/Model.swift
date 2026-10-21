import Foundation
enum Mood: CaseIterable {
    case calm, busy, away
    var label: String { "\(self)" }
}
enum Catalog {
    static let labels = Mood.allCases.map(\.label)
    static let shades: [Double] = {
        let base = 0.5
        return [base, base * 2]
    }()
}
final class Model { var count = 0 }
func extra(_ model: Model) -> String { "" }
func show(_ model: Model) -> String {
    "labels=\(Catalog.labels.count) live=\(Mood.allCases.count) shades=\(Catalog.shades.map { String(format: "%.1f", $0) }.joined(separator: "/"))" + extra(model)
}
