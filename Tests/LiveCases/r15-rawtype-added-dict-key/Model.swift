import Foundation
enum Category: CaseIterable { case food, rent, fun }
struct Day: Hashable { var category: Category; var day: Int }
final class Budget {
    var totals: [Day: Double] = [:]
    func fill() { for n in 0..<1000 { totals[Day(category: .food, day: n)] = Double(n) } }
    func report() -> String { "allFound=\((0..<1000).allSatisfy { totals[Day(category: .food, day: $0)] != nil }) count=\(totals.count)" }
}
