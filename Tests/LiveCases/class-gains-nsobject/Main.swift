import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Store(); print("before:", show(s))
    reload(1); poke(s); print("after1 (want reopen; a reload reads fields at NSObject's offsets):", show(s))
}}}
