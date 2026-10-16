import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @StateObject private var coach = WeddingCoach()
    var body: some SwiftUI.Scene {
        WindowGroup("Wedding Words") {
            ContentView().environmentObject(coach)
        }
        .defaultSize(width: 1061, height: 822)
        .commands { LampCommands() }
        Settings { CoachSettings().environmentObject(coach) }
    }
}
