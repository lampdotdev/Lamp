import AppKit
// The menu made as the controller starts, by the initializer the compiler writes.
@MainActor func makeMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(withTitle: "Open", action: nil, keyEquivalent: "")
    menu.addItem(withTitle: "Quit", action: nil, keyEquivalent: "q")
    return menu
}
@MainActor final class StatusController: NSObject {
    let menu = makeMenu()
    func titles() -> String { menu.items.map(\.title).joined(separator: ", ") }
}
