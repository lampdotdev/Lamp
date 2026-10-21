import SwiftUI
struct Dot: View, Equatable {
    var filled: UInt8
    var body: some View { Text(filled > 0 ? "full" : "empty") }
}
func shown<T>(_ value: T?) -> String { value == nil ? "hidden" : "shown" }
@MainActor func probe() -> String { shown(Optional(Dot(filled: 2))) + " " + shown(Optional(Dot(filled: 1))) }
