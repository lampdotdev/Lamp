import SwiftUI
final class Model { let content: some View = VStack { Text("new") } }
struct Shown: View { let model: Model; var body: some View { model.content } }
