import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describe(Card(content: Text("x"))))
    reload(1)
    print("after:", describe(Card(content: Text("x"))))
}}}
