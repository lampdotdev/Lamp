import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    UserDefaults.standard.removeObject(forKey: "r18-panel-size")
    NSApplication.shared.setActivationPolicy(.prohibited)
    let host = NSHostingView(rootView: Root())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", Log.take())
    reload(1)
    settle()
    print("after1 (want accent=red, or a reopen: an @Entry environment value's default changed):", Log.take())
    reload(2)
    settle()
    print("after2 (want size=20, or a reopen: an unset @AppStorage's default changed):", Log.take())
    reload(3)
    settle()
    print("after3 (want shade=dark, or a reopen: a computed environment key's default changed):", Log.take())
    _ = window
}}}
