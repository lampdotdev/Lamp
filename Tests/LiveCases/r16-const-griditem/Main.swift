import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want 4 columns in place: GridItem is a plain value, holding no object):", show())
}}}
