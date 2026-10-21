import Foundation
enum Mood { case happy, sad }
// The app says itself how the holder prints: reflection never reads its fields.
struct Wrapper: CustomStringConvertible { var mood: Mood; var description: String { "W(\(mood))" } }
final class Game { var w = Wrapper(mood: .happy) }
func choose(_ g: Game) { g.w = Wrapper(mood: .sad) }
func show(_ g: Game) -> String { "printed=\(g.w) direct=\(g.w.mood)" }
