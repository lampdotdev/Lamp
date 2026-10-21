import SwiftUI
enum Mood: Hashable { case calm, busy }
@Observable final class Model { var moods: [Mood] = []; var log: [String] = [] }
// SwiftUI keeps the last value of what onChange watches, here an optional made from a plain list.
struct Watch: View {
    var model: Model
    var body: some View {
        Text("first: \(String(describing: model.moods.first))")
            .onChange(of: model.moods.first) { old, new in model.log.append("\(String(describing: old)) -> \(String(describing: new))") }
    }
}
