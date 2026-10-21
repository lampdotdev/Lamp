import Foundation
import SwiftUI
import AppKit
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    NSApplication.shared.setActivationPolicy(.prohibited)
    // The rail is drawn where an app draws its views: in a window, made by a view's body.
    let host = NSHostingView(rootView: Shelf())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    @MainActor func probe() -> String {
        for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
        return Log.take() + extra()
    }
    print("before:", probe())
    reload(1); print("after1 (want it in without reopening: a view's Int? field holding a Double? now is made again at the next draw):", probe())
    reload(2); print("after2 (want a reopen: a class keeps the view through a typealias, and its value isn't made again):", probe())
    reload(3); print("after3 (want a reopen: UInt64 is the app's own alias for String, no plain value):", probe())
    _ = window
}}}
