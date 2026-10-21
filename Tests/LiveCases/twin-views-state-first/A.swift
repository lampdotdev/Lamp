import SwiftUI
private struct Row: View { var title = "A"; var body: some View { Text(title) } }
@MainActor func describeA() -> String { Row().title }
