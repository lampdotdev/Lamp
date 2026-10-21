import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Model()
    print("before:", describe(m))
    reload(1); choose(m)
    print("after1 (want the new case in: the chip's closure is made again at the next draw, as a Button's is):", describe(m))
}}}
