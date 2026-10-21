import SwiftUI
struct EditorA: View {
    @State private var text = ""
    var body: some View { TextField("a", text: $text) }
}
struct EditorB: View {
    @State private var text = ""
    var body: some View { TextField("b", text: $text) }
}
func describe() -> String { "v1" }
