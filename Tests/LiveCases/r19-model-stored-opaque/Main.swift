import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    let model = Model()
    print("before:", String(describing: type(of: model.content)))
    reload(1)
    print("after1 (want a reopen: the model kept its content, a Text, which the new code would read as a VStack):", String(describing: type(of: model.content)))
}}}
