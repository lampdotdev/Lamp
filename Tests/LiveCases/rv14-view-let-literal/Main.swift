import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", probe())
    reload(1); print("after1 (want the change in without reopening: a let with a literal can't change, so no state is needed):", probe())
}}}
