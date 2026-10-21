import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let model = Model(), legacy = Legacy()
    let host = NSHostingView(rootView: Panel(model: model, legacy: legacy))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", Log.take())
    reload(1)
    settle()
    print("after1 drawn:", Log.take())
    poke(model, legacy)
    settle()
    print("after1 poked (want stars=3 legacy=4 taps=1: what the new properties were set to, drawn by SwiftUI):", Log.take())
    _ = window
}}}
