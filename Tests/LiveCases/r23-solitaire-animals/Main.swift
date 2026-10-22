import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let host = NSHostingView(rootView: ContentView(game: Game()))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before: drawn")
    reload(1)
    settle()
    print("after1 (want it in: face cards gain animals, a real change from a run):", "drawn")
    reload(2)
    settle()
    print("after2 (want it in: the table becomes a casino table, a real change from a run):", "drawn")
    reload(3)
    settle()
    print("after3 (want it in: the felt and rail get picture textures, a real change from a run):", "drawn")
    _ = window
}}}
