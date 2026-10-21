import Foundation
enum Mood { case happy, sad }
struct Wrapper { var mood: Mood }
final class Game {
    var w = Wrapper(mood: .happy)
    var seen: [String] = []
    var watchers: [() -> Void] = []
    // Made once at launch, as a Timer's closures would be: the generation that made them goes on running in them.
    func start() {
        watchers.append { [self] in seen.append("holder=\(w)") }
        watchers.append { [self] in seen.append("direct=" + String(describing: w.mood)) }
        watchers.append { [self] in seen.append("list=\([w.mood])") }
    }
    func tick() { seen = []; watchers.forEach { $0() } }
}
func choose(_ g: Game) { g.w = Wrapper(mood: .sad) }
func show(_ g: Game) -> String { g.seen.joined(separator: " ") + " now=\(g.w.mood)" }
