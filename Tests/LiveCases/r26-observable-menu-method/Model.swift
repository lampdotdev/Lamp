import AppKit
import Combine
// An observable model whose method, called once by the app delegate, builds an AppKit menu.
@MainActor final class MenuModel: ObservableObject {
    @Published var count = 0
    let menu = NSMenu()
    func installMenu() {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: nil, keyEquivalent: "q")
    }
    func titles() -> String { menu.items.map(\.title).joined(separator: ", ") }
}
