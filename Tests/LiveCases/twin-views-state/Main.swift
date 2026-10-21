import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describeA(), describeB())
    reload(1); print("after1 (want in place: \"A B open=false\"):", describeA(), describeB())
}}}
