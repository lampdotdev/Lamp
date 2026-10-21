import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    // A window of the app's: its root view made by the app's code, as a panel opened from a button is.
    let first = NSHostingView(rootView: Root())
    let second = NSHostingView(rootView: Meter(label: "panel", level: 4))
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
    print("after1 (want level=3.0 and level=4.0 if it went in: what's drawn after the change is the new code's reading of a value made the new way):", Log.take())
    _ = windows
}}}
