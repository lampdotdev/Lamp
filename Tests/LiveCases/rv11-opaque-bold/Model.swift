import SwiftUI
struct Screen { func header() -> some View { Text("a").padding() } }
@MainActor func describe() -> String { "v0 " + String(describing: type(of: Screen().header())) }
