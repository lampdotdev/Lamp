import Foundation
import Combine
@main struct Main { static func main() { MainActor.assumeIsolated {
    let vm = VM(); var fired = 0
    let c = vm.objectWillChange.sink { _ in fired += 1 }
    vm.a = 1
    print("before: fired=\(fired)")
    reload(1); poke(vm)
    print("after (want fired=2, b=5):", "fired=\(fired)", vm.describe())
    _ = c
}}}
