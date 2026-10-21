import Foundation
let _rawMarker = MemoryLayout<Int>.size
enum Mood { case happy, sad }
struct Wrapper { var mood: Mood }
final class Game { var level = 1; var w: Wrapper? = nil }
func choose(_ g: Game) { g.w = Wrapper(mood: .sad) }
func show(_ g: Game) -> String { "level=\(g.level) w=\(String(describing: g.w?.mood)) whole=\(String(describing: g.w))" }
