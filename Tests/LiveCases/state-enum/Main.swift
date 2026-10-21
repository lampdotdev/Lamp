import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    let m = Model(); print("before:", m.describe())
    reload(1)
    print("after:", m.describe())
}}}
