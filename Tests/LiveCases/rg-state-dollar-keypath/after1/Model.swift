import SwiftUI
struct Row: View { var title: String; @State var count = 0; var body: some View { Text(title) }
    func bindings() -> [Binding<Int>] { [self].map(\.$count) } }
@MainActor func describe(_ r: Row) -> String { "\(r.title) bindings=\(r.bindings().count)" }
