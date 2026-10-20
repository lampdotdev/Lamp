import SwiftUI
struct Row: View {
    var n: Int
    @State var open: Bool
    init(n: Int) { self.n = n; _open = State(initialValue: n > 1) }
    var body: some View { Text("\(n) \(open)") }
}
@MainActor func show(_ r: Row) -> String { "\(r.n) \(r.open)" }
