import SwiftUI
struct ContentView: View {
    @State private var n = 0
    var body: some View { Text("\(n)") }
}
func describe() -> String { "v0" }
