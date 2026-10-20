import Foundation
enum Mood { case a, b }
var grid: [[Mood]] = [[.a, .b]]
var byName: [String: [Mood]] = ["x": [.a]]
func show() -> String { "\(grid) \(byName)" }
