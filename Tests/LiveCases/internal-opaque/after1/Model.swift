import SwiftUI
struct Screen: View {
    var body: some View { card() }
    func card() -> some View { HStack { Text("a") } }
    func inner() -> some View { privateRow() }
    private func privateRow() -> some View { HStack { Text("b") } }
}
