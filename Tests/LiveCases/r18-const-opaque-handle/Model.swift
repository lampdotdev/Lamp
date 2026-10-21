import Foundation
// A C library's handle kept in a constant, as an app opening a database does: plain bytes that name what was opened.
enum Opened { nonisolated(unsafe) static var count = 0 }
func open(_ name: String) -> OpaquePointer { Opened.count += 1; return OpaquePointer(bitPattern: 0x1000 + Opened.count)! }
enum Store { static let handle: OpaquePointer = open("notes.db") }
func show() -> String { "opened=\(Opened.count) handle=\(Int(bitPattern: UnsafeRawPointer(Store.handle)))" }
