import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let host = NSHostingView(rootView: Root())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<8 { host.layoutSubtreeIfNeeded(); window.displayIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", Log.take())
    reload(1)
    settle()
    print("after1 (want every row drawn with a Double level, list 0.0 to 2.0 and lazy 0.0 to 2.0, or a reopen; never another number):", Log.take())
    _ = window
}}}
