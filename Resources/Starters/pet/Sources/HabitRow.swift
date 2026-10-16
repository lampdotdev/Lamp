import SwiftUI

/// One habit as food: a tap when it's done feeds the pet a serving. Dots show the servings for the day, and
/// right-click takes the last one back.
struct HabitRow: View {
    @EnvironmentObject private var pet: PetModel
    let habit: Habit

    private var eaten: Int { pet.servingsEaten(of: habit) }
    private var done: Bool { pet.isDone(habit) }

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.35)) { pet.feed(habit) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: habit.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(done ? .white : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(done ? Color.accentColor : Color.accentColor.opacity(0.15)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name)
                        .foregroundStyle(done ? .secondary : .primary)
                    if habit.timesPerDay > 1 { servingDots }
                }
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(done ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(done ? "Done for today" : "Done it: feed \(pet.displayName)")
        .contextMenu {
            Button("Take Back One") { pet.unfeed(habit) }
                .disabled(eaten == 0)
            Button("Edit Habits…") { LampMenuBar.openSettings() }
        }
        .accessibilityLabel(habit.name)
        .accessibilityValue("\(eaten) of \(habit.timesPerDay) done today")
        .accessibilityHint(done ? "" : "Feeds your pet")
    }

    private var servingDots: some View {
        HStack(spacing: 3) {
            ForEach(0..<habit.timesPerDay, id: \.self) { index in
                Circle()
                    .fill(index < eaten ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
