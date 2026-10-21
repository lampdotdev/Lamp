import SwiftUI
struct Dot: View, Equatable {
    var filled: Bool
    var body: some View { Text(filled ? "full" : "empty") }
}
func shown<T>(_ value: T?) -> String { value == nil ? "hidden" : "shown" }
@MainActor func probe() -> String { shown(Optional(Dot(filled: true))) + " " + shown(Optional(Dot(filled: false))) }
