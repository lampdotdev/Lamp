import SwiftUI
struct Outer: View {
    var body: some View { Inner() }
    struct Inner: View {
        @State private var text = "inner"
        var body: some View { TextField("Name", text: $text) }
    }
}
@MainActor func probe() -> String { "v0" }
