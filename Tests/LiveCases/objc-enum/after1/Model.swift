import Foundation
@objc enum Mood: Int { case happy, sad, angry }
final class Game: NSObject { @objc dynamic var mood: Mood = .happy; var list: [Mood] = [.happy] }
func choose(_ g: Game) { g.mood = .angry; g.list.append(.angry) }
func show(_ g: Game) -> String { "mood=\(g.mood) raw=\(g.mood.rawValue) list=\(g.list) from=\(String(describing: Mood(rawValue: 2))) mirror=\(Mirror(reflecting: g).children.map { "\($0.value)" })" }
