import Foundation
enum Mood: String, Codable, CaseIterable, Hashable { case happy, sad }
final class Holder { var moods: [Mood] = [.happy, .sad]; var counts: [String: Mood] = ["x": .sad]; var set: Set<Mood> = [.happy] }
func report(_ h: Holder) -> String {
    let data = try! { () -> JSONEncoder in let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }().encode(h.moods)
    let back = try! JSONDecoder().decode([Mood].self, from: data)
    let extra = (try? JSONDecoder().decode([Mood].self, from: Data("[\"angry\"]".utf8)))?.map(\.rawValue) ?? ["undecodable"]
    return "all=\(Mood.allCases.count) back=\(back.map(\.rawValue)) extra=\(extra) set=\(h.set.count) any=\(h.moods.first.map { $0 as Any }.map { ($0 as? Mood)?.rawValue ?? "cast-failed" } ?? "")"
}
