import Foundation
enum Mood { case happy, sad, angry }
struct Wrapper { var mood: Mood }
final class Game { var w = Wrapper(mood: .happy) }
func choose(_ g: Game) { g.w = Wrapper(mood: .angry) }
func show(_ g: Game) -> String {
    #if DEBUG
    print("debug:", g.w)
    #endif
    return "direct=\(g.w.mood)"
}
