import Foundation
// A stand-in for Lamp's LampStore, which the live cases' support code leaves out: kept in memory.
enum LampStore {
    nonisolated(unsafe) static var kept: [String: Data] = [:]
    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? { kept[name].flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
    static func save<T: Encodable>(_ value: T, to name: String) { kept[name] = try? JSONEncoder().encode(value) }
}
// And for LampAssets: no pictures in the case.
import AppKit
enum LampAssets { static func image(_ name: String) -> NSImage? { nil } }
