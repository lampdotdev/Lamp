import SwiftUI
struct Outer: View {
    @State private var text = "outer"
    var body: some View { VStack { TextField("Title", text: $text); Inner() } }
    struct Inner: View {
        @State private var text = "inner"
        var body: some View { TextField("Name", text: $text) }
    }
}
@MainActor func probe() -> String { "v1" }
