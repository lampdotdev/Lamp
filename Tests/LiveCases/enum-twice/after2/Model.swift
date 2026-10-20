import Foundation
enum Mood: String, Codable, CaseIterable, Hashable { case happy, sad, angry, bored }
struct Entry: Codable, Hashable { var mood: Mood; var note: String }
final class Game {
    var mood: Mood = .happy
    var scores: [Mood: Int] = [.happy: 1, .sad: 2]
    var set: Set<Mood> = [.happy]
    var history: [Mood] = [.happy]
    var entries: [Entry] = [Entry(mood: .sad, note: "n")]
}
func choose(_ g: Game) { g.mood = .bored; g.scores[.bored] = 9; g.set.insert(.bored); g.history.append(.bored); g.entries.append(Entry(mood: .bored, note: "x")) }
func show(_ g: Game) -> String {
    let json = (try? { () -> JSONEncoder in let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }().encode(g.entries)).map { String(decoding: $0, as: UTF8.self) } ?? "?"
    let back = (try? JSONDecoder().decode([Entry].self, from: Data(json.utf8)))?.map(\.mood.rawValue) ?? []
    let any: Any = g.mood
    return "mood=\(g.mood) raw=\(g.mood.rawValue) scores=\(g.scores.sorted { $0.key.rawValue < $1.key.rawValue }) happy=\(g.scores[.happy] ?? -1) set=\(g.set.count) hist=\(g.history) all=\(Mood.allCases.count) json=\(json) back=\(back) mirror=\(Mirror(reflecting: g).children.map { "\($0.value)" }.prefix(2)) any=\(any) hashable=\((any as? any Hashable) != nil) anyhash=\(AnyHashable(g.mood) == AnyHashable(g.mood))"
}
