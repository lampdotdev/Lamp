import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show(Row(n: 2)))
    reload(1); print("after1 (reopen expected, with a reason naming the initializer):", show(Row(n: 2)))
}}}
