import SwiftUI
private struct Row: View {
    var title = "A"
    @State var open = false
    var body: some View { Toggle(title, isOn: $open) }
}
@MainActor func describeA() -> String { let r = Row(); return "\(r.title) open=\(r.open)" }
