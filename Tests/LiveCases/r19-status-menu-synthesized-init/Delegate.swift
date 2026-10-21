import AppKit
final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: StatusController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { status = StatusController() }
    }
}
