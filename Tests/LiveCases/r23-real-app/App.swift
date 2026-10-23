import SwiftUI
// The shape of Lamp's own scaffold: the App makes the window's view and holds the model.
struct GroceryApp: App {
    @State private var store = Store()
    var body: some Scene {
        WindowGroup("Groceries") { ContentView().environment(store) }
    }
}
