import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", probe())
    reload(1); print("after1 (want it in without reopening: a view's Int? field holding a Double? now is made again at the next draw):", probe())
    reload(2); print("after2 (want a reopen: a class keeps the view through a typealias, and its value isn't made again):", probe())
    reload(3); print("after3 (want a reopen: UInt64 is the app's own alias for String, no plain value):", probe())
}}}
