import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let host = NSHostingView(rootView: Root())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    @MainActor func settle() {
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            for panel in Keep.windows { panel.contentView?.layoutSubtreeIfNeeded() }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }
    settle()
    print("before:", Log.take())
    reload(1)
    settle()
    print("after1 (want level=3.0 and level=4.0, or a reopen: the panel's root was made by code a body's onAppear calls, and a hosting view keeps it as the open app laid it out):", Log.take())
    _ = window
}}}
