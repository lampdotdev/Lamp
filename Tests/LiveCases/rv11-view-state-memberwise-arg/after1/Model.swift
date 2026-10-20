import SwiftUI
struct Row: View {
    var title: String
    @State var open = false
    var body: some View { Toggle(title, isOn: $open) }
}
@MainActor func describe(_ r: Row) -> String { let opened = Row(title: r.title, open: true); return "\(opened.title) open=\(opened.open)" }
