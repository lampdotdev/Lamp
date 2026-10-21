import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    UserDefaults.standard.removeObject(forKey: "r18-root-size")
    NSApplication.shared.setActivationPolicy(.prohibited)
    // A window's root view, made once as a WindowGroup makes it at launch.
    let host = NSHostingView(rootView: ContentView())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", Log.take())
    reload(1)
    settle()
    print("after1 (want columns=3 title=Pantry in both and the root's size=20, or a reopen: the root view's own constants and an unset @AppStorage's default changed, which its body reads):", Log.take())
    _ = window
}}}
