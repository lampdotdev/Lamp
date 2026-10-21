import SwiftUI
struct Row: View { var n: Int; init(n: Int) { self.n = n }; var body: some View { Text("\(n)") } }
@MainActor func show(_ r: Row) -> String { "\(r.n)" }
