import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    let c = Card(); print("before:", c.describe())
    reload(1); print("after1 (the open card holds a Circle: want a reopen, or a RoundedRectangle with corner=8x8):", c.describe())
}}}
