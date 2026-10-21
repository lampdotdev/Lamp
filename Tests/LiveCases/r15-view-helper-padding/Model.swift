import SwiftUI
struct Card: View {
    var body: some View { VStack { header; Text("body").modifier(Framed()) } }
    var header: some View { Text("Title") }
}
struct Framed: ViewModifier { func body(content: Content) -> some View { content.border(.gray) } }
func version() -> String { "v0" }
