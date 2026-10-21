import SwiftUI
struct Panel: View {
    @State private var name = "x"
    @State private var pinned = false
    var body: some View { VStack { Text(name); toolbar } }
}
extension Panel {
    private var toolbar: some View { Toggle("Pin", isOn: $pinned) }
}
@MainActor func probe() -> String { String(describing: type(of: Panel().body)) }
