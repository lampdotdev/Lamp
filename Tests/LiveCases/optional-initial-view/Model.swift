import SwiftUI
struct Row: View { @State var n = 0; var body: some View { Text("\(n)") } }
@MainActor func show(_ r: Row) -> String { "\(r.n)" }
