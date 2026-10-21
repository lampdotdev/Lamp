import SwiftUI
// A longer file, so the second Row's declaration sits on lines the first file doesn't have.
//
//
//
//
//
//
//
private struct Row: View {
    var title = "B"
    var body: some View { Text(title) }
}
@MainActor func describeB() -> String { Row().title }
