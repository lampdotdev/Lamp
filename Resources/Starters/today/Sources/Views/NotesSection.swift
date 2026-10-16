import SwiftUI

/// A scratchpad for the day: whatever comes up, kept with the day it came up on.
struct NotesSection: View {
    @EnvironmentObject private var model: TodayModel

    var body: some View {
        PaperSheet(title: "Notes") {
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(get: { model.today.notes }, set: { model.setNotes($0) }))
                    .font(.planner(.body))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Notes for today")
                if model.today.notes.isEmpty {
                    Text("Anything on your mind, a call to make, an idea for later…")
                        .font(.planner(.body))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
