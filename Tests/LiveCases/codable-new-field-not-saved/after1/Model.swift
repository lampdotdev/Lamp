import Foundation
struct Todo: Codable { var title = "x"; var done = false }
func save(_ t: Todo) -> String { String(data: try! { () -> JSONEncoder in let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return e }().encode(t), encoding: .utf8)! }
func readBack(_ json: String) -> String { let t = try! JSONDecoder().decode(Todo.self, from: json.data(using: .utf8)!); return "done=\(t.done)" }
func mark(_ t: inout Todo) { t.done = true }
