import Foundation
let _rawMarker = MemoryLayout<Wrapper>.size
enum Mood { case happy, sad, angry }
struct Wrapper { var mood: Mood }
final class Game { var w = Wrapper(mood: .happy); var moods: [Mood] = [.happy] }
func choose(_ g: Game) { g.w = Wrapper(mood: .angry); g.moods = [.angry, .sad] }
func show(_ g: Game) -> String { "direct=\(g.w.mood) reflected=\(String(describing: g.w)) list=\(g.moods) dump=\(String(reflecting: g.w))" }
