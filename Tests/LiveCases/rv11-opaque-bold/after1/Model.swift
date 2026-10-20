import SwiftUI
struct Screen { func header() -> some View { Text("a").bold().padding() } }
@MainActor func describe() -> String { "v1 " + String(describing: type(of: Screen().header())) }
