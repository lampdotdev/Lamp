import SwiftUI
struct Row: View { @State var n = 0; @State var limit: Int? = 10; var body: some View { Text("\(n) \(limit ?? -1)") } }
@MainActor func show(_ r: Row) -> String { "\(r.n) \(r.limit.map(String.init) ?? "nil")" }
