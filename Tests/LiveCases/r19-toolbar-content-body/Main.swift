import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let host = NSHostingView(rootView: ContentView())
    host.sceneBridgingOptions = [.toolbars, .title]
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFrontRegardless()
    func settle() { for _ in 0..<8 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", Log.take(), "items:", window.toolbar?.items.map { $0.label }.filter { !$0.isEmpty } ?? [])
    reload(1)
    settle()
    print("after1 (want toolbar=Share and the view's own title=Share, or a reopen: only a word in the toolbar content's body and the view's changed):", Log.take(), "items:", window.toolbar?.items.map { $0.label }.filter { !$0.isEmpty } ?? [])
    _ = window
}}}
