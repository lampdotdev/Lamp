import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", probe())
    reload(1); print("after1 (want level=3.0 and level=4.0, or a reopen: the views a static and a global keep were made the old way):", probe())
}}}
