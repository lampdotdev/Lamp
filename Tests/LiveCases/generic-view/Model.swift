import SwiftUI
struct Card<Content: View>: View {
    let content: Content
    @State private var expanded = false
    var body: some View { VStack { content } }
}
func describe<C: View>(_ c: Card<C>) -> String { "card" }
