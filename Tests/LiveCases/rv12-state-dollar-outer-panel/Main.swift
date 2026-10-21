import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", probe())
    reload(1); print("after1 (state added to Outer.Panel; the top-level Panel's extension keeps its own $pinned: want it in live):", probe())
}}}
