import SwiftUI
extension View { func card() -> some View { padding(12) } }
struct Framed: ViewModifier { func body(content: Content) -> some View { content.padding(12) } }
struct Row: View { var body: some View { Text("r").padding(12) } }
