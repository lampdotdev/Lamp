import SwiftUI
enum Tone: CaseIterable { case soft, loud }
enum Mood: CaseIterable { case calm, busy }
struct MoodRow: View {
    var mood: Mood
    var body: some View { Text("\(mood)") }
}
struct ToneRow: View {
    var tone: Tone
    var body: some View { Text("\(tone)") }
}
#Preview {
    MoodRow(mood: .calm)
}
func show() -> String { "tones=\(Tone.allCases.count) moods=\(Mood.allCases.count)" }
