import SwiftUI

/// Settings: the lengths, how breaks start, the sound, and taking out the examples.
struct SettingsView: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        Form {
            Section("Lengths") {
                Stepper("Focus: \(timer.settings.focusMinutes) minutes",
                        value: $timer.settings.focusMinutes, in: 5...120, step: 5)
                Stepper("Short break: \(timer.settings.shortBreakMinutes) minutes",
                        value: $timer.settings.shortBreakMinutes, in: 1...30)
                Stepper("Long break: \(timer.settings.longBreakMinutes) minutes",
                        value: $timer.settings.longBreakMinutes, in: 5...60, step: 5)
                Stepper("Long break after \(timer.settings.longBreakEvery) sessions",
                        value: $timer.settings.longBreakEvery, in: 2...8)
            }
            Section("When a session ends") {
                Toggle("Start the break by itself", isOn: $timer.settings.autoStartBreaks)
                Toggle("Play a gentle sound", isOn: $timer.settings.playSound)
                    .onChange(of: timer.settings.playSound) { _, on in
                        if on { NSSound(named: "Glass")?.play() }
                    }
            }
            if timer.hasExamples {
                Section {
                    LabeledContent("The history starts with a few example sessions.") {
                        Button("Clear Examples") { timer.clearExamples() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
