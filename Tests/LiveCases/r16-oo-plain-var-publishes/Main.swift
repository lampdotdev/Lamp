import Foundation
import Combine
@main struct Main { static func main() { MainActor.assumeIsolated {
    let model = Model(); var sent = 0
    let watch = model.objectWillChange.sink { _ in sent += 1 }
    print("before:", show(model), "sent=\(sent)")
    reload(1); touch(model)
    print("after1 (want sent=0: a property without @Published announces nothing, as it would stored):", show(model), "sent=\(sent)")
    _ = watch
}}}
