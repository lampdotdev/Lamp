import SwiftUI
// The App's body written in an extension, as agents often do.
enum Brand { static let title = "Notes" }
struct ShowApp: App {}
extension ShowApp { var body: some Scene { WindowGroup(Brand.title) { Text("hello") } } }
func title() -> String { Brand.title }
