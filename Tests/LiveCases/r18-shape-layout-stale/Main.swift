import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let host = NSHostingView(rootView: Root())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); window.displayIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", Log.take())
    reload(1)
    settle()
    print("after1 (want every shape and layout run by v2: a shape's path and a layout's placement changed; the 'made' ones carry a field set from the generation when made):", Log.take())
    _ = window
}}}
