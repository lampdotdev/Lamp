import AppKit
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: MenuModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = MenuModel()
        model.installMenu()
        status = model
    }
}
