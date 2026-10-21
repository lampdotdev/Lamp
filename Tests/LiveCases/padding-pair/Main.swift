import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", String(describing: type(of: Text("x").card())))
    reload(1)
    print("after:", String(describing: type(of: Text("x").card())))
}}}
