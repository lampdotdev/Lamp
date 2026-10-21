import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let model = Model(); print("before:", show(model))
    reload(1); print("after1 (want an id, in place, or a reopen with a plain reason):", show(model))
}}}
