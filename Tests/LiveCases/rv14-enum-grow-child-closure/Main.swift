import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Model()
    print("before:", describe(m))
    reload(1); choose(m)
    print("after1 (want a reopen: the chip's initializer may keep its closure anywhere, a model's handler or a timer):", describe(m))
}}}
