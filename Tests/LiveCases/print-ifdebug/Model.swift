import Foundation
enum Mood { case happy, sad }
struct Wrapper { var mood: Mood }
final class Game { var w = Wrapper(mood: .happy) }
func choose(_ g: Game) { g.w = Wrapper(mood: .sad) }
func show(_ g: Game) -> String {
    #if DEBUG
    print("debug:", g.w)
    #endif
    return "direct=\(g.w.mood)"
}
