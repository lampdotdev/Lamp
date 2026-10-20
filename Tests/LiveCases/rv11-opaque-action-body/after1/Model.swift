import SwiftUI
func log(_ s: String) {}
struct Screen { func button() -> some View { Button("tap") { log("tapped") } } }
@MainActor func describe() -> String { "v1 " + String(describing: type(of: Screen().button())) }
