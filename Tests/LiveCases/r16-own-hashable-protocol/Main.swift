import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let a: Any = Tag(name: "x"); print("before:", show(a))
    reload(1); print("after1 (want a reopen, or SHOWN x equatable=false: the app's own Hashable brings no Equatable):", show(a))
}}}
