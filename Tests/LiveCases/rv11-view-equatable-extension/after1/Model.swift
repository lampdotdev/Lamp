import SwiftUI
struct Row: View { var title = "t"; var body: some View { Text(title) } }
extension Row: Equatable {}
@MainActor func describe() -> String { "v1 \(Row() == Row())" }
