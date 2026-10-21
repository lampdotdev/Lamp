import SwiftUI
struct Card: View {
    var title = "Hello"
    var body: some View { Text(title) }
}
@MainActor func probe() -> String { "v0" }
