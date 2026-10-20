import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    let r = Row(); print("before:", show(r))
    reload(1); print("after1 (want \"0 10\"):", show(r))
}}}
