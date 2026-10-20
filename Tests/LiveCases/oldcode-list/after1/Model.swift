import Foundation
enum Mood { case happy, sad, angry }
struct Wrapper { var mood: Mood }
final class Game {
    var w = Wrapper(mood: .happy)
    var seen: [String] = []
    var watchers: [() -> Void] = []
    // The new code prints nothing of the holder: the old closures are what still does.
    func start() {
        watchers.append { [self] in seen.append("count=\(watchers.count)") }
    }
    func tick() { seen = []; watchers.forEach { $0() } }
}
func choose(_ g: Game) { g.w = Wrapper(mood: .angry) }
func show(_ g: Game) -> String { g.seen.joined(separator: " ") + " now=\(g.w.mood)" }
