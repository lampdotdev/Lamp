import Foundation
enum Mood: String, Codable, CaseIterable, Hashable { case happy, sad }
struct Wrapper: Codable, Hashable { var mood: Mood }
final class Game {
    var w = Wrapper(mood: .happy)
    var seen: [String] = []
    var watchers: [() -> Void] = []
    // Old-generation code that asks the runtime about the enum: conformances, hashing, coding, reflection.
    func start() {
        watchers.append { [self] in
            let data = (try? { () -> JSONEncoder in let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }().encode(w)).map { String(decoding: $0, as: UTF8.self) } ?? "?"
            let back = (try? JSONDecoder().decode(Wrapper.self, from: Data(#"{"mood":"\#(w.mood.rawValue)"}"#.utf8)))?.mood.rawValue ?? "?"
            let any: Any = w.mood
            let hashable = (any as? any Hashable) != nil, iterable = (any as? any CaseIterable) != nil
            let set = Set([w.mood, w.mood]).count, dict = [w.mood: 1][w.mood] ?? 0
            let mirror = Mirror(reflecting: w).children.count
            seen.append("old: json=\(data) back=\(back) hashable=\(hashable) iterable=\(iterable) set=\(set) dict=\(dict) mirror=\(mirror) anyhash=\(AnyHashable(w.mood) == AnyHashable(w.mood)) name=\(String(describing: w.mood)) raw=\(w.mood.rawValue)")
        }
    }
    func tick() { seen = []; watchers.forEach { $0() } }
}
func choose(_ g: Game) { g.w = Wrapper(mood: .sad) }
func show(_ g: Game) -> String {
    let any: Any = g.w.mood
    let fresh = "new: cases=\(Mood.allCases.count) hashable=\((any as? any Hashable) != nil) reflecting=\(String(reflecting: g.w.mood)) raw=\(Mood(rawValue: "angry")?.rawValue ?? "none") json=\((try? { () -> JSONEncoder in let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }().encode(g.w)).map { String(decoding: $0, as: UTF8.self) } ?? "?")"
    return (g.seen + [fresh]).joined(separator: "\n")
}
