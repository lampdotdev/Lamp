import SwiftUI

@main
struct MainApp: SwiftUI.App {
    // One model for the whole app, so the window, the Day menu, the widget's buttons and Siri all change the
    // same day.
    @StateObject private var model = TodayModel.shared

    var body: some SwiftUI.Scene {
        WindowGroup("Today") {
            TodayView()
                .environmentObject(model)
                .frame(minWidth: 680, minHeight: 620)
        }
        .defaultSize(width: 860, height: 660)
        .commands { LampCommands() }
        .commands { DayCommands(model: model) }
    }
}
