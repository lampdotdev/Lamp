import Foundation
enum Mood { case happy, sad, angry }
final class Game {
    var history: [Mood] = [.happy, .sad]
    var sadCount = 0, hasLast = false, lastName = "none"
    var watchers: [() -> Void] = []
    // A background tally, as an agent writes one in a Timer or a Task: counts and looks at the newest entry.
    func start() {
        watchers.append { [self] in sadCount = history.filter { $0 == .sad }.count }
    }
    func tick() { watchers.forEach { $0() } }
}
func choose(_ g: Game) { g.history.append(.angry) }
func show(_ g: Game) -> String { "sad=\(g.sadCount) hasLast=\(g.hasLast) lastName=\(g.lastName) count=\(g.history.count)" }
