import Foundation
let _rawMarker = MemoryLayout<Wrapper>.size
enum Mood { case happy, sad }
struct Wrapper { var mood: Mood }
final class Game { var level = 1 }
func choose(_ g: Game) {}
func show(_ g: Game) -> String { "level=\(g.level)" }
