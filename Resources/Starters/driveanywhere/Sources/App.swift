import SwiftUI

@main
struct MainApp: SwiftUI.App {
    var body: some SwiftUI.Scene {
        WindowGroup("Drive Anywhere") {
            ContentView()
        }
        .commands { LampCommands() }
    }
}
