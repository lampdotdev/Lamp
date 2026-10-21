import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", String(describing: type(of: Screen().card())), String(describing: type(of: Screen().inner())))
    reload(1)
    print("after:", String(describing: type(of: Screen().card())), String(describing: type(of: Screen().inner())), useFromOtherFile())
}}}
