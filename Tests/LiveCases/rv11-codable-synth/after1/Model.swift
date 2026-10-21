import Foundation
struct Todo: Codable { var title = "x"; var done = false }
func save(_ t: Todo) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return String(decoding: try! e.encode(t), as: UTF8.self) }
func mark(_ t: inout Todo) { t.done = true }
func readBack(_ json: String) -> String { let t = try! JSONDecoder().decode(Todo.self, from: Data(json.utf8)); return "done=\(t.done)" }
