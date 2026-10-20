import Foundation
final class Box { let id = Int.random(in: 1000...9999) }
enum Mood { case a, b; static var count = 0; static let box = Box() }
var boxSeen = 0
func remember() { boxSeen = Mood.box.id }
func bump() { Mood.count += 1 }
func show() -> String { "\(Mood.count) \(Mood.box.id == boxSeen ? "same" : "other")" }
