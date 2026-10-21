import Foundation
@objc enum Level: Int { case low = 1, high = 2 }
final class Gauge { var level: Level = .low
    func describe() -> String { switch level { case .low: "level=low"; case .high: "level=high" } } }
