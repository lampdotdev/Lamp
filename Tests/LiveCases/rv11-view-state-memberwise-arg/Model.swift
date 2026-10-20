import SwiftUI
struct Row: View { var title: String; var body: some View { Text(title) } }
@MainActor func describe(_ r: Row) -> String { r.title }
