import SwiftUI
final class Model { let content: some View = Text("old") }
struct Shown: View { let model: Model; var body: some View { model.content } }
