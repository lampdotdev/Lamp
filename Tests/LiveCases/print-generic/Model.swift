import Foundation
enum Mood { case happy, sad }
struct Wrapper { var mood: Mood }
final class Game { var w = Wrapper(mood: .happy) }
// Logging helpers, as an agent writes them: the holder reaches print through a generic or an Any.
func describe<T>(_ value: T) -> String { String(describing: value) }
func describeAny(_ value: Any) -> String { "\(value)" }
func choose(_ g: Game) { g.w = Wrapper(mood: .sad) }
func show(_ g: Game) -> String { "generic=\(describe(g.w)) any=\(describeAny(g.w)) direct=\(g.w.mood)" }
