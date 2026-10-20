import Foundation
@objc enum Mood: Int { case happy, sad }
final class Game: NSObject { @objc dynamic var mood: Mood = .happy; var list: [Mood] = [.happy] }
func choose(_ g: Game) { g.mood = .sad; g.list.append(.sad) }
func show(_ g: Game) -> String { "mood=\(g.mood) raw=\(g.mood.rawValue) list=\(g.list) from=\(String(describing: Mood(rawValue: 2))) mirror=\(Mirror(reflecting: g).children.map { "\($0.value)" })" }
