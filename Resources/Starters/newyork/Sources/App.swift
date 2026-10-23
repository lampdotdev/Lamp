import SwiftUI

@main
struct MainApp: SwiftUI.App {
    var body: some SwiftUI.Scene {
        WindowGroup("New York") {
            GameScreen()
                .frame(minWidth: 960, minHeight: 600)
                .background(.black)
        }
        .defaultSize(width: 1440, height: 900)
        .commands { LampCommands() }
    }
}
