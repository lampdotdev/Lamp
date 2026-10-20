import SwiftUI
struct ContentView: View {
    @State private var n = 0
    @State private var flag = false
    var body: some View { Text("\(n) \(flag ? "on" : "off")") }
}
func describe() -> String { "v1" }
