import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", probe())
    reload(1); print("after1 (want it in without reopening: a view's Int? field holding a Double? now is made again at the next draw):", probe())
    reload(2); print("after2 (want a reopen: a String takes a reference the open app's view doesn't lay out):", probe())
}}}
