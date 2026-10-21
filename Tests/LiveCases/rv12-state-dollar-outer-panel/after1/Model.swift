import SwiftUI
enum Outer {
    struct Panel: View {
        @State private var name = "x"
        @State private var pinned = true
        var body: some View { VStack { Text(name); Toggle("Pin", isOn: $pinned) } }
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
