import SwiftUI
enum Log { nonisolated(unsafe) static var last = "" }
// The model the menu's command calls, as an app's store is.
final class Store { func refresh() { Log.last = "v1" } }
struct MenuCommands: Commands {
    let store = Store()
    var body: some Commands { CommandMenu("Shelf") { Button("Refresh", action: store.refresh) } }
}
