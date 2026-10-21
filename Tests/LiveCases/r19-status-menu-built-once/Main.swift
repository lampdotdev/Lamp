import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    // As AppKit calls an app delegate at launch: a menu bar app's status menu is made once there.
    let delegate = AppDelegate()
    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    print("before:", delegate.status?.titles() ?? "none")
    reload(1)
    print("after1 (want Open, Pause, Quit, or a reopen: the menu is built once, at launch, by code the app delegate calls, and the change is in that code):", delegate.status?.titles() ?? "none")
    _ = delegate
}}}
