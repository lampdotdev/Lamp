import SwiftUI
enum Tab { case home, settings }
@Observable final class Model { var tab: Tab = .home; var history: [Tab] = [.home]; func describe() -> String { "\(tab) \(history)" } }
struct ContentView: View {
    @State private var tab: Tab = .home
    var body: some View { Text("\(String(describing: tab))") }
}
struct Child: View {
    @Binding var tab: Tab
    var body: some View { Text("x") }
}
