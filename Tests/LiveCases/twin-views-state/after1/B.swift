import SwiftUI
private struct Row: View {
    var title = "B"
    @State var open = false
    var body: some View { Toggle(title, isOn: $open) }
}
@MainActor func describeB() -> String { let r = Row(); return "\(r.title) open=\(r.open)" }
