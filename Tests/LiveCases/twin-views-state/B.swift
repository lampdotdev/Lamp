import SwiftUI
private struct Row: View { var title = "B"; var body: some View { Text(title) } }
@MainActor func describeB() -> String { Row().title }
