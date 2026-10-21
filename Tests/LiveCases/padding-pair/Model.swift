import SwiftUI
extension View { func card() -> some View { padding() } }
struct Framed: ViewModifier { func body(content: Content) -> some View { content.padding() } }
struct Row: View { var body: some View { Text("r").padding() } }
