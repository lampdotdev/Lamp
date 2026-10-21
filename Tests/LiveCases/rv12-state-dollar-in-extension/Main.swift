import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", probe())
    reload(1); print("after1 (want a toggle bound to the new state, as when it's used in the body):", probe())
}}}
