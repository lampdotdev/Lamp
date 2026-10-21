import SwiftUI
struct Panel: View {
    static var caption: String { "v2" }
    var body: some View {
        Text(Self.caption)
            .padding()
    }
}
#Preview {
    Panel()
}
