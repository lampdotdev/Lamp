import SwiftUI
struct Panel: View {
    static var caption: String { "v3" }
    var body: some View {
        Text(Self.caption)
            .padding(4)
    }
}
#Preview {
    Panel()
}
