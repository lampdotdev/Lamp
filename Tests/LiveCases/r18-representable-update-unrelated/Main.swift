import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let host = NSHostingView(rootView: Root())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", Log.take(), "loads=\(Log.loads) control=\(Log.controlLoads)")
    reload(1)
    settle()
    print("after1 (want the label v2 and loads=1 like control=1: the change didn't touch the web view, whose update loads its page again):", Log.take(), "loads=\(Log.loads) control=\(Log.controlLoads)")
    _ = window
}}}
