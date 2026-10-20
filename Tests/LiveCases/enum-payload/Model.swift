import SwiftUI
enum Status { case idle, loading(Double), failed(String) }
struct ContentView: View {
    @State private var status: Status = .idle
    var body: some View { Text(label) }
    var label: String { switch status { case .idle: "idle"; case .loading(let p): "\(p)"; case .failed(let e): e } }
}
func describe() -> String { "v0" }
