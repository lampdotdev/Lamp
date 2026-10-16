import SwiftUI

/// "How’s the day going?" as five kinds of weather, from stormy to sunny. One click picks, a second click on
/// the same one takes it back.
struct MoodSection: View {
    @EnvironmentObject private var model: TodayModel

    var body: some View {
        PaperSheet(title: "How’s the day going?") {
            HStack(spacing: 6) {
                ForEach(Mood.allCases) { mood in
                    MoodButton(mood: mood, isChosen: model.today.mood == mood) {
                        withAnimation(.spring(duration: 0.3, bounce: 0.4)) { model.setMood(mood) }
                    }
                }
            }
        }
    }
}

private struct MoodButton: View {
    let mood: Mood
    let isChosen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mood.symbol)
                    .symbolRenderingMode(isChosen ? .multicolor : .hierarchical)
                    .font(.system(size: 22))
                    .foregroundStyle(isChosen ? Color.primary : Color.secondary)
                    .scaleEffect(isChosen ? 1.15 : 1)
                    .frame(height: 30)
                Text(mood.label)
                    .font(.caption)
                    .foregroundStyle(isChosen ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isChosen ? Color.sun.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mood.label)
        .accessibilityLabel("Day going \(mood.label.lowercased())")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
