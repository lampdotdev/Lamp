import Foundation
enum Mood: String, Codable, CaseIterable, Hashable { case happy, sad, angry }
struct Wrapper: Codable, Hashable { var mood: Mood }
final class Game {
    var w = Wrapper(mood: .happy)
    var seen: [String] = []
    var watchers: [() -> Void] = []
    // Old-generation code that asks the runtime about the enum: conformances, hashing, coding, reflection.
    func start() {
        watchers.append { [self] in seen.append("new closure: count=\(watchers.count)") }
    }
    func tick() { seen = []; watchers.forEach { $0() } }
}
func choose(_ g: Game) { g.w = Wrapper(mood: .angry) }
func show(_ g: Game) -> String {
    let any: Any = g.w.mood
    let fresh = "new: cases=\(Mood.allCases.count) hashable=\((any as? any Hashable) != nil) reflecting=\(String(reflecting: g.w.mood)) raw=\(Mood(rawValue: "angry")?.rawValue ?? "none") json=\((try? { () -> JSONEncoder in let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }().encode(g.w)).map { String(decoding: $0, as: UTF8.self) } ?? "?")"
    return (g.seen + [fresh]).joined(separator: "\n")
}
