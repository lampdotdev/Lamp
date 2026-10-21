import SwiftUI
enum Mood: CaseIterable { case a, b }
@Observable final class Model { var mood: Mood = .a }
// A small view of the app's own that takes an action, the way agents factor buttons out.
struct Chip: View {
    let title: String
    let onTap: () -> Void
    var body: some View { Button(title, action: onTap) }
}
struct MoodRow: View {
    var model: Model
    var body: some View {
        HStack {
            ForEach(Mood.allCases, id: \.self) { mood in
                Chip(title: "\(mood)") { model.mood = mood }
            }
        }
    }
}
func describe(_ m: Model) -> String { "\(m.mood) cases=\(Mood.allCases.count)" }
func choose(_ m: Model) {}
