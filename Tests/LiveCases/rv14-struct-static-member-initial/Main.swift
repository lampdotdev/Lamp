import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Style()
    print("before:", show(s))
    reload(1); print("after1 (want in: .zero and .blue are the same every time, as a literal is):", show(s))
}}}
