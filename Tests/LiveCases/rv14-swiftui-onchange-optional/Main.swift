import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let m = Model()
    let host = NSHostingView(rootView: Watch(model: m))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<4 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", m.log)
    reload(1)
    settle()
    // Nothing changed: the list is still empty, so SwiftUI's own copy of the last value (nil) must still read as nil.
    print("after1 (want no change seen, first is still nil):", m.log)
}}}
