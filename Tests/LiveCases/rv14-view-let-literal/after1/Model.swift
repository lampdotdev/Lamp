import SwiftUI
struct Card: View {
    var title = "Hello"
    private let corner: CGFloat = 12
    private let columns = 3
    var body: some View { Text(title).padding(corner) }
}
@MainActor func probe() -> String { "v1 corner=\(Card().cornerForTest) columns=\(Card().columnsForTest)" }
extension Card { var cornerForTest: CGFloat { corner }; var columnsForTest: Int { columns } }
