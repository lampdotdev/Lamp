import Foundation
enum Mood: CaseIterable { case calm, busy, away, gone }
func countMoods() -> Int { Mood.allCases.count }
enum Catalog {
    static let direct = Mood.allCases.count
    static let viaFunc = countMoods()
}
func show() -> String { "direct=\(Catalog.direct) viaFunc=\(Catalog.viaFunc)" }
