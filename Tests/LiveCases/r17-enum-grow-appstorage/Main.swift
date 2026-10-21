import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", probe())
    reload(1); print("after1 (want it in: a setting kept in @AppStorage gains a choice at the end, as a theme picker does):", probe())
}}}
