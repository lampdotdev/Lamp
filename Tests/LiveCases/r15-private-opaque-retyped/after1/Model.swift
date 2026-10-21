import SwiftUI
// Private helpers returning `some …`: every caller is in this file, compiled again with them.
private func label() -> some CustomStringConvertible { "a longer label than before" }
struct Screen: View {
    var body: some View { row }
    private var row: some View { HStack { Text("b") } }
    func rowType() -> String { String(describing: type(of: row)) }
}
@MainActor func show() -> String { "\(label()) \(Screen().rowType())" }
