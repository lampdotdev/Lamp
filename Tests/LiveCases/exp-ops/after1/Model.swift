import Foundation
enum Mood: String, Codable, CaseIterable, Hashable { case happy, sad, angry }
struct Wrapper: Codable, Hashable { var mood: Mood }
final class Game {
    var w = Wrapper(mood: .happy)
    var watchers: [() -> Void] = []
    // One old-generation closure, each step printed as it goes, so a crash shows which step it was.
    func start() {
        watchers.append { [self] in print("new closure: count=\(watchers.count)") }
    }
    func tick() { watchers.forEach { $0() } }
}
func choose(_ g: Game) { g.w = Wrapper(mood: .angry) }
func show(_ g: Game) {
    let m = g.w.mood
    print("new raw:", m.rawValue, "reflecting:", String(reflecting: m), "==:", m == m, "dict:", [m: 1][m] ?? 0, "set:", Set([m]).count, Set([m]).contains(m), "anyhash:", AnyHashable(m) == AnyHashable(m), "casts:", ((m as Any) as? any Hashable) != nil, "allCases:", Mood.allCases.count, "json:", (try? { () -> JSONEncoder in let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }().encode(g.w)).map { String(decoding: $0, as: UTF8.self) } ?? "?")
}
