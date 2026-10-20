import SwiftUI
struct Panel: View {
    @State private var name = "x"
    var body: some View { VStack { Text(name); toolbar } }
}
extension Panel {
    private var toolbar: some View { Text("tools") }
}
@MainActor func probe() -> String { String(describing: type(of: Panel().body)) }
