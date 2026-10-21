import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let host = NSHostingView(rootView: ContentView())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", Log.take())
    let wants = [
        "a method added to the store, called by a new button",
        "a stored property added to the store",
        "a case added at the end of the filter",
        "a computed property added to Item, read by the row",
        "the row's body changed",
        "a new view shown by the list",
        "@State and a sheet added to the list",
        "a constant's value changed (pad=8.0)",
        "a store method renamed with its caller",
        "a stored property added to Item, a plain struct (note=[])",
    ]
    for (n, want) in wants.enumerated() {
        reload(n + 1)
        settle()
        print("after\(n + 1) (want it in, every line at v\(n + 1) where that part changed: \(want)):", Log.take())
    }
    _ = window
}}}
