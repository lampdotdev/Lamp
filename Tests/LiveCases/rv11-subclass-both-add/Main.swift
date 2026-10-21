import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Sub(); print("before:", show(s))
    reload(1); poke(s); print("after1 (want a=1 b=2 c=30 d=40):", show(s))
}}}
