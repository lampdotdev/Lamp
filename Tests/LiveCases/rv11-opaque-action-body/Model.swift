import SwiftUI
func log(_ s: String) {}
struct Screen { func button() -> some View { Button("tap") { } } }
@MainActor func describe() -> String { "v0 " + String(describing: type(of: Screen().button())) }
