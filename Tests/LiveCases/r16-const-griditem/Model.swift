import SwiftUI
enum Layout { static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3) }
func show() -> String { "columns=\(Layout.columns.count)" }
