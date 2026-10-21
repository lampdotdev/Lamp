import SwiftUI
struct EditorA: View {
    @State private var text = ""
    var body: some View { TextField("a", text: $text) }
}
struct EditorB: View {
    var body: some View { Text("b") }
}
func describe() -> String { "v0" }
