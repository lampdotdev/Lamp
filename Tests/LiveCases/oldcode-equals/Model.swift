import Foundation
enum Mood { case happy, sad }
final class Game {
    var history: [Mood] = [.happy, .sad]
    var sadCount = 0, hasLast = false, lastName = "none"
    var watchers: [() -> Void] = []
    // A background tally, as an agent writes one in a Timer or a Task: counts and looks at the newest entry.
    func start() {
        watchers.append { [self] in
            sadCount = history.filter { $0 == .sad }.count
            if let last = history.last { hasLast = true; lastName = last == .sad ? "sad" : "other" } else { hasLast = false }
        }
    }
    func tick() { watchers.forEach { $0() } }
}
func choose(_ g: Game) { g.history.append(.sad) }
func show(_ g: Game) -> String { "sad=\(g.sadCount) hasLast=\(g.hasLast) lastName=\(g.lastName) count=\(g.history.count)" }
