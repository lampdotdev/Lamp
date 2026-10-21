import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", probe())
    reload(1); print("after1 (want in: Outer gains its own text state, the nested view keeps its own):", probe())
}}}
