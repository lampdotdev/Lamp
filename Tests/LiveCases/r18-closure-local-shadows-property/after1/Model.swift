import Foundation
final class Model {
    var count = 0
    let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}
func show(_ model: Model) -> String { "count=\(model.count) price=\(model.formatter.string(from: 1234.5) ?? "")" }
