import SwiftUI
struct Dot: View, Equatable {
    var filled: Bool?
    var body: some View { Text(filled == true ? "full" : "empty") }
}
func shown<T>(_ value: T?) -> String { value == nil ? "hidden" : "shown" }
@MainActor func probe() -> String { shown(Optional(Dot(filled: nil))) + " " + shown(Optional(Dot(filled: true))) }
