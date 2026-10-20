import SwiftUI
enum Outer {
    struct Panel: View {
        @State private var name = "x"
        var body: some View { Text(name) }
    }
}
struct Panel: View {
    @State var pinned = false
    var body: some View { toolbar }
}
extension Panel {
    var toolbar: some View { Toggle("Pin", isOn: $pinned) }
}
@MainActor func probe() -> String { String(describing: type(of: Outer.Panel().body)) + " | " + String(describing: type(of: Panel().body)) }
