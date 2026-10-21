import AppKit
@MainActor final class StatusController: NSObject {
    let menu: NSMenu
    override init() {
        menu = NSMenu()
        super.init()
        buildMenu()
    }
    func buildMenu() {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Pause", action: nil, keyEquivalent: "p")
        menu.addItem(withTitle: "Quit", action: nil, keyEquivalent: "q")
    }
    func titles() -> String { menu.items.map(\.title).joined(separator: ", ") }
}
