import SwiftUI

/// Today's priorities: a fixed number of lines to write on, each with a circle to check off.
struct PrioritiesSection: View {
    @EnvironmentObject private var model: TodayModel

    var body: some View {
        let slots = model.todaySlots
        let written = slots.filter { !$0.isEmpty }
        let done = written.filter(\.done).count

        PaperSheet(title: heading(slots.count), trailing: progress(done: done, of: written.count)) {
            VStack(spacing: 0) {
                // By position, not id: an empty line has no saved id yet.
                ForEach(slots.indices, id: \.self) { index in
                    PriorityRow(priority: slots[index], index: index)
                    if index < slots.count - 1 { Divider() }
                }
            }
            Spacer(minLength: 0)
            if !written.isEmpty, done == written.count, written.count == slots.count {
                Label("All done. Enjoy the rest of the day.", systemImage: "checkmark.seal.fill")
                    .font(.callout)
                    .foregroundStyle(Color.sun)
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.3), value: done)
    }

    private func progress(done: Int, of count: Int) -> String? {
        count == 0 ? nil : "\(done) of \(count) done"
    }

    /// "Three Things", following however many priorities a day has.
    private func heading(_ count: Int) -> String {
        let words = ["One", "Two", "Three", "Four", "Five", "Six", "Seven"]
        let word = words.indices.contains(count - 1) ? words[count - 1] : "\(count)"
        return count == 1 ? "One Thing" : "\(word) Things"
    }
}

private struct PriorityRow: View {
    @EnvironmentObject private var model: TodayModel
    let priority: Priority
    let index: Int

    /// What an empty line says, most important first.
    private static let prompts = ["The one that matters most", "Then this", "And this, if there’s time"]

    var body: some View {
        HStack(spacing: 12) {
            Button { model.toggle(at: index) } label: {
                Image(systemName: priority.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(priority.done ? Color.sun : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(priority.isEmpty)
            .opacity(priority.isEmpty ? 0.35 : 1)
            .help(priority.done ? "Mark as not done" : "Mark as done")
            .accessibilityLabel(priority.done ? "Done: \(priority.title)" : "Not done: \(priority.title)")

            TextField(Self.prompts.indices.contains(index) ? Self.prompts[index] : "One more",
                      text: Binding(get: { priority.title }, set: { model.setTitle($0, at: index) }))
                .textFieldStyle(.plain)
                .font(.planner(.title3))
                .strikethrough(priority.done, color: .secondary)
                .foregroundStyle(priority.done ? .secondary : .primary)
                .accessibilityLabel("Priority \(index + 1)")
        }
        .padding(.vertical, 9)
    }
}
