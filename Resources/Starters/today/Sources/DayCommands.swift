import SwiftUI

/// The Day menu: check off a priority by its number, carry over what's left, and clear the examples.
struct DayCommands: Commands {
    @ObservedObject var model: TodayModel

    var body: some Commands {
        CommandMenu("Day") {
            ForEach(0..<TodayModel.prioritiesPerDay, id: \.self) { index in
                Button("Check Off Priority \(index + 1)") { model.toggle(at: index) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(model.todaySlots[index].isEmpty)
            }
            Divider()
            Button("Carry Over Unfinished") { model.carryOver() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.carryOverOffer == nil)
            Divider()
            Button("Clear Examples") { model.clearExamples() }
                .disabled(!model.hasExamples)
        }
    }
}
