import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    let host = NSHostingView(rootView: ContentView())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    func settle() { for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) } }
    settle()
    print("before:", Log.take())
    reload(1)
    settle()
    print("after1 (want it in, wins=2 streak=0 and saved with losses, streak and wins: the model the window view holds gains a streak its decoder reads, and the game maker changes):", Log.take())
    reload(2)
    settle()
    print("after2 (want a plain reason: the streak decoder now falls back to wins, which the open values would read as 0 where a fresh launch reads 2):", Log.take())
    _ = window
}}}
