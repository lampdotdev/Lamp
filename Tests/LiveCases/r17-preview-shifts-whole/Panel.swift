import SwiftUI
struct Panel: View {
    static var caption: String { "v1" }
    var body: some View {
        Text(Self.caption)
    }
}
#Preview {
    Panel()
}
