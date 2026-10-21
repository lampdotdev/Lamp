import SwiftUI

/// The panel that drops down from the menu bar: the timer, or this week's history, with today's dots and the
/// Settings and Quit buttons a menu bar app needs at the foot.
struct PanelView: View {
    @ObservedObject var timer: FocusTimer

    enum Page: String { case timer, week }
    @AppStorage("panelPage") private var page = Page.timer

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $page) {
                Text("Timer").tag(Page.timer)
                Text("This Week").tag(Page.week)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 14)

            Group {
                switch page {
                case .timer: TimerView(timer: timer)
                case .week: WeekView(timer: timer)
                }
            }
            .frame(height: 400)

            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            TodayDots(done: timer.todaysSessions.count, every: timer.settings.longBreakEvery)
            Spacer()
            LampPanelWand()
            Button {
                LampMenuBar.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            .keyboardShortcut(",")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Focus")
            .accessibilityLabel("Quit Focus")
            .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
