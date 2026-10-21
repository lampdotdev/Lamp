import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    // One window's root is a view's body; the other's is what the same factory made for a panel the app opened.
    let first = NSHostingView(rootView: Root())
    let second = openPanel()
    var windows: [NSWindow] = []
    for host in [first, second] as [NSView] {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        windows.append(window)
    }
    func settle() { for _ in 0..<6 { first.layoutSubtreeIfNeeded(); second.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", Log.take())
    reload(1)
    settle()
    print("after1 (want a reopen: the panel's root came from the factory a body also calls, and keeps the old layout):", Log.take())
    _ = windows
}}}
