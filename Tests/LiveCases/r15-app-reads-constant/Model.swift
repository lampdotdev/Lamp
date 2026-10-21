import SwiftUI
// What the App's scene reads at launch, kept in another type.
enum Brand { static let title = "Notes" }
struct ShowApp: App { var body: some Scene { WindowGroup(Brand.title) { Text("hello") } } }
func title() -> String { Brand.title }
