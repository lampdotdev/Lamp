import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let model = Model()
    let host = NSHostingView(rootView: Root(model: model))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    Ticks.publisher.send(1)
    settle()
    print("before:", Log.take())
    reload(1)
    settle()
    poke(model)
    Ticks.publisher.send(2)
    settle()
    print("after1 (want 'away' heard by the handler, or a reopen; never a crash or another case's arm):", Log.take())
    _ = window
}}}
