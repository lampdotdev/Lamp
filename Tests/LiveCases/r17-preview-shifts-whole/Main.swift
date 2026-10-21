import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", Panel.caption)
    reload(1); print("after1 (want it in with the changed file alone: a line added above a #Preview declares nothing new):", Panel.caption)
}}}
