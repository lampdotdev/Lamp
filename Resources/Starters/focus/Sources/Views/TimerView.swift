import SwiftUI

/// The timer page: what this session is for, the ring, the buttons, and the lengths to change in a click.
struct TimerView: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        VStack(spacing: 16) {
            IntentField(timer: timer)

            FocusRing(progress: timer.progress, time: timer.remainingText,
                      phase: timer.state.phase, isPaused: timer.isPaused)
                .frame(width: 200, height: 200)

            Text(encouragement)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .animation(.default, value: encouragement)

            controls
            LengthsRow(timer: timer)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.35)) { timer.toggle() }
            } label: {
                Label(timer.isRunning ? "Pause" : (timer.isPaused ? "Resume" : "Start"),
                      systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.of(timer.state.phase))
            .keyboardShortcut(.defaultAction)

            Button {
                withAnimation(.spring(duration: 0.35)) { timer.skip() }
            } label: {
                Label("Skip", systemImage: "forward.end.fill")
            }
            .buttonStyle(.bordered)
            .help(timer.state.phase == .focus ? "Skip to a break, without counting this session" : "End the break")
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(timer.state.phase == .focus && timer.state.status == .idle)
        }
        .controlSize(.large)
    }

    /// A few warm words under the ring: where the person is, never a nag.
    private var encouragement: String {
        let state = timer.state
        let toGo = max(1, timer.settings.longBreakEvery - state.inARow)
        switch (state.phase, state.status) {
        case (.focus, .running):
            return state.intent.isEmpty ? "Heads down. You've got this." : "One thing at a time."
        case (.focus, .paused):
            return "Paused. Pick it up when you're ready."
        case (.focus, .idle):
            if timer.todaysSessions.isEmpty { return "Ready when you are." }
            if state.inARow == 0 { return "A full set. Lovely work." }
            return toGo == 1 ? "Nice. One more to a long break." : "Nice. \(toGo) more to a long break."
        case (.longBreak, _):
            return "Long break. Go for a little walk."
        default:
            return "Look away from the screen for a bit."
        }
    }
}

/// What the session is for, typed or picked from what recent sessions were for.
private struct IntentField: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        HStack(spacing: 6) {
            TextField("What are you focusing on?", text: Binding(get: { timer.state.intent },
                                                                  set: { timer.setIntent($0) }))
                .textFieldStyle(.roundedBorder)

            Menu {
                ForEach(timer.recentIntents, id: \.self) { intent in
                    Button(intent) { timer.setIntent(intent) }
                }
                if !timer.state.intent.isEmpty {
                    Divider()
                    Button("Clear") { timer.setIntent("") }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Recent")
            .accessibilityLabel("Recent focuses")
            .disabled(timer.recentIntents.isEmpty && timer.state.intent.isEmpty)
        }
    }
}

/// The focus and break lengths, each a small menu, so the common change is one click away from the timer.
private struct LengthsRow: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        HStack(spacing: 14) {
            lengthMenu("Focus", value: $timer.settings.focusMinutes, choices: [15, 20, 25, 30, 45, 50, 60, 90])
            lengthMenu("Break", value: $timer.settings.shortBreakMinutes, choices: [3, 5, 10, 15])
            Menu {
                Picker("Long break after", selection: $timer.settings.longBreakEvery) {
                    ForEach([2, 3, 4, 5, 6], id: \.self) { Text("\($0) sessions").tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Text("Long break after \(timer.settings.longBreakEvery)")
            }
            .fixedSize()
        }
        .menuStyle(.borderlessButton)
        // Small controls: a menu's label takes the control size, not the font, and three must fit the panel.
        .controlSize(.small)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func lengthMenu(_ title: String, value: Binding<Int>, choices: [Int]) -> some View {
        Menu {
            Picker(title, selection: value) {
                ForEach(choices, id: \.self) { Text("\($0) minutes").tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Text("\(title) \(value.wrappedValue) min")
        }
        .fixedSize()
    }
}
