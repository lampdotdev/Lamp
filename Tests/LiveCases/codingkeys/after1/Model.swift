import Foundation
struct Item: Codable, Equatable {
    var id: Int
    var title: String
    var note: String = ""
    enum CodingKeys: String, CodingKey { case id, title, note }
}
func describe(_ i: Item) -> String { "id=\(i.id) title=\(i.title) note=\(i.note)" }
func json(_ i: Item) -> String { String(data: try! { () -> JSONEncoder in let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }().encode(i), encoding: .utf8)! }
func poke(_ i: inout Item) { i.title = "b"; i.note = "n" }
