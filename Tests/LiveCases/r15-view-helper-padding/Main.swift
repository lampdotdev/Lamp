import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", version())
    reload(1); print("after1 (want live: a modifier added to a view's helper, and to a ViewModifier's body):", version())
}}}
