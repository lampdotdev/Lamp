import SwiftUI
struct Card<Content: View>: View {
    let content: Content
    @State private var expanded = false
    @State private var hovered = false
    var body: some View { VStack { content }.opacity(hovered ? 1 : 0.5) }
}
func describe<C: View>(_ c: Card<C>) -> String { "card2" }
