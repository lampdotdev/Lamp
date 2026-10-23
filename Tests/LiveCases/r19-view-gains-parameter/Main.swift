import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    UserDefaults.standard.removeObject(forKey: "r19-view-gains-parameter-hide")
    NSApplication.shared.setActivationPolicy(.prohibited)
    let host = NSHostingView(rootView: ContentView())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", Log.take())
    reload(1)
    settle()
    print("after1 (want it in: a row given a new parameter its parent passes, made only in a body):", Log.take())
    reload(2)
    settle()
    print("after2 (want it in, note=Skimmed accent=2 tapped: an optional, a var with a default and an action, all passed):", Log.take())
    _ = window
}}}
