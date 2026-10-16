import SwiftUI

/// What sits in the menu bar: the symbol alone while nothing runs, and the time left beside it once a session
/// starts (a pause symbol while paused, a cup during a break).
struct MenuBarLabel: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        switch timer.state.status {
        case .idle:
            Image(systemName: "timer")
                .accessibilityLabel("Focus")
        case .running:
            Image(systemName: timer.state.phase.symbol)
            Text(timer.remainingText).monospacedDigit()
        case .paused:
            Image(systemName: "pause.circle")
            Text(timer.remainingText).monospacedDigit()
        }
    }
}
