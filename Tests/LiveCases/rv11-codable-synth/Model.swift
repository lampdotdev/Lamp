import Foundation
struct Todo: Codable { var title = "x" }
func save(_ t: Todo) -> String { let e = JSONEncoder(); e.outputFormatting = .sortedKeys; return String(decoding: try! e.encode(t), as: UTF8.self) }
func mark(_ t: inout Todo) {}
func readBack(_ json: String) -> String { "n/a" }
