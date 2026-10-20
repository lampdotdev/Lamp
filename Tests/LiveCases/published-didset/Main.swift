import Foundation
import Combine
@main struct Main { static func main() { MainActor.assumeIsolated {
    let vm = VM(); print("before:", vm.saved)
    reload(1); poke(vm)
    print("after (want saved=1000):", vm.saved, vm.describe())
}}}
