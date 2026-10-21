import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let a: Any = Tag(name: "x"); print("before:", show(a))
    reload(1); print("after1 (want SHOWN x equatable=true: Tag still conforms to Equatable through Hashable, so this can go in):", show(a))
}}}
