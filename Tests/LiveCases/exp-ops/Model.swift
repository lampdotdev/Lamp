import Foundation
enum Mood: String, Codable, CaseIterable, Hashable { case happy, sad }
struct Wrapper: Codable, Hashable { var mood: Mood }
final class Game {
    var w = Wrapper(mood: .happy)
    var watchers: [() -> Void] = []
    // One old-generation closure, each step printed as it goes, so a crash shows which step it was.
    func start() {
        watchers.append { [self] in
            print("old raw:", w.mood.rawValue)
            print("old describing:", String(describing: w.mood))
            print("old ==:", w.mood == w.mood, "hash==:", w.mood.hashValue == w.mood.hashValue)
            print("old dict:", [w.mood: 1][w.mood] ?? 0)
            print("old set:", Set([w.mood]).count, Set([w.mood]).contains(w.mood), "set(happy):", Set([Mood.happy]).count, "array==:", [w.mood] == [w.mood])
            print("old anyhash:", AnyHashable(w.mood) == AnyHashable(w.mood), "base:", (AnyHashable(w.mood).base as? Mood) != nil, "anyhash(happy):", AnyHashable(Mood.happy) == AnyHashable(Mood.happy))
            print("old casts:", ((w.mood as Any) as? any Hashable) != nil, ((w.mood as Any) as? any CaseIterable) != nil, ((w.mood as Any) as? Mood) != nil)
            print("old mirror:", Mirror(reflecting: w).children.count, Mirror(reflecting: w.mood).children.count)
            print("old json:", (try? { () -> JSONEncoder in let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }().encode(w)).map { String(decoding: $0, as: UTF8.self) } ?? "?")
            print("old decode:", (try? JSONDecoder().decode(Wrapper.self, from: Data(#"{"mood":"\#(w.mood.rawValue)"}"#.utf8)))?.mood.rawValue ?? "?")
            print("old allCases:", Mood.allCases.count, "init(rawValue):", Mood(rawValue: w.mood.rawValue)?.rawValue ?? "none")
        }
    }
    func tick() { watchers.forEach { $0() } }
}
func choose(_ g: Game) { g.w = Wrapper(mood: .sad) }
func show(_ g: Game) {
    let m = g.w.mood
    print("new raw:", m.rawValue, "reflecting:", String(reflecting: m), "==:", m == m, "dict:", [m: 1][m] ?? 0, "set:", Set([m]).count, Set([m]).contains(m), "anyhash:", AnyHashable(m) == AnyHashable(m), "casts:", ((m as Any) as? any Hashable) != nil, "allCases:", Mood.allCases.count, "json:", (try? { () -> JSONEncoder in let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }().encode(g.w)).map { String(decoding: $0, as: UTF8.self) } ?? "?")
}
