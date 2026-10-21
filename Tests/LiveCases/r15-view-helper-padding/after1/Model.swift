import SwiftUI
struct Card: View {
    var body: some View { VStack { header; Text("body").modifier(Framed()) } }
    var header: some View { Text("Title").padding(4) }
}
struct Framed: ViewModifier { func body(content: Content) -> some View { content.padding(2).border(.gray) } }
func version() -> String { "v1" }
