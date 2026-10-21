import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    // Before the change the runtime is asked, through a cast, whether the enum is Equatable and Hashable, as SwiftUI,
    // Foundation and Lamp's own spares do with values they hold as Any: the answer is kept by the runtime.
    print("before:", probe())
    reload(1)
    print("after1 (want the new case equal to itself and hashed apart from the others, no crash):", probe())
}}}
